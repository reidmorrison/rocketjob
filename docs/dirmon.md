---
layout: default
---

## Directory Monitoring
{:.no_toc}

**Contents**

* TOC
{:toc}

Watching a directory for new files and kicking off a job to process each one is one of the most
common tasks in any batch processing system. Almost every team ends up writing it themselves, along
with all the awkward parts: detecting when a file has finished uploading, archiving it so it is not
picked up twice, retrying after failures, and securing which directories may be read.

Rocket Job ships this as a built-in feature called **Dirmon** (Directory Monitor). Because it is part
of Rocket Job it also comes with a full management screen in
[Rocket Job Mission Control](mission_control.html), the web UI, so files, schedules, and failures can
be managed without writing or deploying any code.

Dirmon is driven by two pieces:

* `RocketJob::Jobs::DirmonJob` is a scheduled job that scans the configured directories on a fixed
  interval (every 5 minutes by default).
* `RocketJob::DirmonEntry` is a persisted record describing *one* thing to watch: a path pattern, the
  job class to start, where to archive processed files, and any fields to set on that job.

The key idea is that **a `DirmonEntry` can populate the fields of the job it starts**. A new file is
not just handed to a job: the entry decides which job class runs and pre-sets its fields. That is what
makes Dirmon able to launch any user-defined or built-in job, fully configured, for each incoming
file.

## Why per-entry job fields matter

A very common deployment looks like this: customers upload files over SFTP, each into their own
account-specific directory. The files all need the same processing, but the job needs to know *which
account* a file belongs to, and often a few other details such as an email address to notify when the
output is ready for pickup.

With Dirmon this is solved by creating one `DirmonEntry` per account. Each entry watches that account's
directory and sets the account-specific fields on the job through its `properties` hash:

~~~ruby
class CustomerImportJob < RocketJob::Job
  include RocketJob::Batch

  # Keep the job after completion so the output file can be downloaded.
  self.destroy_on_complete = false

  # Account that owns this file. Set per DirmonEntry.
  # `user_editable: true` also makes it editable in Mission Control.
  field :account_id, type: Integer, user_editable: true

  # Where to send the "your file is ready" notification.
  field :notify_email, type: String, user_editable: true

  input_category serializer: :encrypt
  output_category

  after_batch :notify_when_ready

  # Called once per record, spread across all available workers.
  def perform(row)
    Importer.new(account_id: account_id).transform(row)
  end

  private

  def notify_when_ready
    CustomerMailer.import_complete(notify_email, id).deliver_later if notify_email
  end
end
~~~

Create one entry per account, each setting the fields specific to that account:

~~~ruby
RocketJob::DirmonEntry.create!(
  name:              "ACME customer imports",
  pattern:           "/var/sftp/acme/incoming/*.csv",
  job_class_name:    "CustomerImportJob",
  archive_directory: "/var/sftp/acme/archive",
  properties:        {
    account_id:   42,
    notify_email: "ops@acme.example.com",
    priority:     25
  }
).enable!

RocketJob::DirmonEntry.create!(
  name:              "Globex customer imports",
  pattern:           "/var/sftp/globex/incoming/*.csv",
  job_class_name:    "CustomerImportJob",
  archive_directory: "/var/sftp/globex/archive",
  properties:        {
    account_id:   77,
    notify_email: "files@globex.example.com"
  }
).enable!
~~~

Now any file dropped into `/var/sftp/acme/incoming` starts a `CustomerImportJob` with `account_id`
`42` and the ACME notification address, while files for Globex start the same job scoped to their own
account. The processing code is written once; the per-account context comes from the entry.

The `properties` hash can set **any field on the target job that has a writer**, including the
built-in fields such as `priority`, `description`, and `run_at`, as well as the batch
`input_categories` / `output_categories`. Setting a value for a field the job does not define is
rejected by validation, so a typo fails fast when the entry is saved rather than silently doing
nothing.

> Fields that should also be editable from the Mission Control web UI must be declared with
> `user_editable: true`, as shown above. Setting `properties` programmatically does not require it.

## How a scan works

`DirmonJob` does not start a job the instant a file appears, because the file may still be uploading.
Instead it waits for the file to stabilize:

1. On each run it lists the files matching every enabled entry's `pattern`.
2. A newly seen file's size is recorded and carried forward to the next run.
3. On the next run, if the file's size is unchanged, it is considered complete and its job is started.
   If the size changed, it is recorded again and rechecked on the following run.

This means a file is normally picked up one scan interval after it finishes uploading. Object stores
are a special case: on stores where partial files are not visible until the upload completes (such as
Amazon S3), the file is processed on the first scan that sees it, with no stabilization wait.

When a file is ready, Dirmon archives it first and then starts the job, so the same file can never be
picked up twice (see [Archiving](#archiving)).

## Creating a DirmonEntry

~~~ruby
entry = RocketJob::DirmonEntry.create!(
  name:              "Daily price feed",
  pattern:           "/data/prices/*.csv",
  job_class_name:    "PriceFeedJob",
  archive_directory: "/data/prices/archive",
  properties:        { priority: 30 }
)
~~~

The fields of `DirmonEntry`:

* **`pattern`** (required, String)
  A path glob used to find files. Standard `Dir.glob` wildcards apply, evaluated through
  [IOStreams](https://github.com/reidmorrison/iostreams) so local paths and remote paths (SFTP, S3,
  and so on) are supported. Examples:
    * `input_files/process1/*.csv`
    * `input_files/process2/**/*` (all files, recursively)
    * `input_files/process2/*.{csv,txt}` (multiple extensions)
  If the pattern contains no `*`, it is treated as an exact file name. Patterns are unique across all
  entries, which helps prevent two entries from claiming the same files.

* **`job_class_name`** (required, String)
  Name of the job class to start for each matching file. The class must be defined and inherit from
  `RocketJob::Job`.

* **`archive_directory`** (required, String, defaults to `archive`)
  Where matching files are moved before their job is started. See [Archiving](#archiving).

* **`properties`** (Hash, defaults to `{}`)
  Fields to set on the job that is started, as described in
  [Why per-entry job fields matter](#why-per-entry-job-fields-matter).

* **`name`** (String, optional but recommended)
  A human-readable label used to identify the entry in Mission Control. Names must be unique.

## Enabling and disabling entries

A new `DirmonEntry` starts in the `pending` state and is **not** scanned until it is enabled. This is
deliberate: an entry can be reviewed before it goes live.

~~~ruby
entry.enable!     # pending/disabled/failed -> enabled
entry.disable!    # enabled/failed -> disabled
~~~

The states are:

* **`pending`** – newly created, not yet scanned.
* **`enabled`** – actively scanned by `DirmonJob`.
* **`disabled`** – manually paused.
* **`failed`** – an error occurred while processing the entry (for example a security violation or an
  unreadable path). The entry is removed from scanning until it is re-enabled. The cause is stored in
  the entry's embedded `exception`.

A snapshot of how many entries are in each state:

~~~ruby
RocketJob::DirmonEntry.counts_by_state
# => { pending: 1, enabled: 37, disabled: 3, failed: 1 }
~~~

## How the file reaches the job

When a file stabilizes, Dirmon archives it and enqueues a `RocketJob::Jobs::UploadFileJob`, which
builds the target job from the entry's `properties` and then hands the archived file to it. How the
file is delivered depends on what the job supports:

* **Batch jobs** (`include RocketJob::Batch`) implement `#upload`, so the file's contents are uploaded
  directly into the job's input, split into slices, and processed in parallel. This is the usual case
  for file processing.
* **Simple jobs** can instead declare an `upload_file_name` or `full_file_name` field; the absolute
  path of the archived file is assigned to it, leaving the job to open and read the file itself.

A job that is neither a batch job nor declares one of those fields cannot be used as a Dirmon target
and is rejected by validation.

## Archiving

Before a job is started, the file is **moved** to the entry's `archive_directory`. Moving first
guarantees the file is out of the watched path before processing begins, so it cannot be discovered
again on a later scan. The archived file name is prefixed with the downstream job's id, which ties the
stored file to the job that processed it.

* If `archive_directory` is an **absolute** path, files are moved there directly.
* If it is a **relative** path, it is resolved relative to the directory the file was found in, and any
  sub-directory structure under the pattern is preserved.
* If left unset it defaults to a directory named `archive`.

## Security: restricting which paths may be read

A `pattern` can point anywhere the process user can read, so Dirmon supports an allow-list of root
paths. When any paths are registered, every resolved file must live under one of them or it is skipped
and a warning is logged.

~~~ruby
# In an initializer, not via the web UI, so it cannot be tampered with.
RocketJob::DirmonEntry.add_whitelist_path("/var/sftp")

RocketJob::DirmonEntry.get_whitelist_paths
# => ["/var/sftp"]

RocketJob::DirmonEntry.delete_whitelist_path("/var/sftp")
~~~

Notes:

* If no paths are registered, the check is skipped entirely.
* Registering a path confirms it exists (`realpath` is resolved), so absolute paths are recommended.
  Relative paths are accepted but are not considered safe, since they can be manipulated.
* These should be set in application code (an initializer), not made editable in the web UI.

## Starting the directory monitor

Dirmon scanning is itself a scheduled Rocket Job, so it must be started once per installation:

~~~ruby
RocketJob::Jobs::DirmonJob.create!
~~~

`DirmonJob` is a [cron job](guide.html) that runs every 5 minutes (`*/5 * * * * UTC`) at priority 30.
Override either when creating it:

~~~ruby
RocketJob::Jobs::DirmonJob.create!(
  cron_schedule: "*/1 * * * * UTC",
  priority:      25
)
~~~

The schedule and priority can be changed at any time afterwards, either from Mission Control or in
code:

~~~ruby
RocketJob::Jobs::DirmonJob.first.update_attributes(
  cron_schedule: "*/5 * * * * UTC",
  priority:      20
)
~~~

Starting a second `DirmonJob` while one is already queued or running is rejected with a validation
error, so it is safe to call `create!` from deploy automation guarded by a rescue, or use the
non-raising `create`.

## High availability

`DirmonJob` has no dedicated process and no single point of failure. After each scan completes it
schedules the next instance of itself and then destroys the current one. Because Rocket Job picks any
available worker for the next run, scanning continues even as individual workers and containers come
and go. There is only ever one `DirmonJob` queued or running at a time.

If a scan raises an exception, the responsible `DirmonEntry` is moved to the `failed` state with the
exception recorded, so the rest of the entries keep working and the failure can be investigated and
re-enabled from Mission Control.

## Managing Dirmon in the web UI

Everything above can be done from [Rocket Job Mission Control](mission_control.html): create and edit
entries, set their `user_editable` job fields, enable, disable, and re-enable them, inspect failures,
and adjust the `DirmonJob` schedule and priority. Because Dirmon ships with Rocket Job, this UI is
available with no extra code, which is exactly what teams otherwise rebuild by hand for every project.

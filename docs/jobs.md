---
layout: default
---

## Included Jobs
{:.no_toc}

**Contents**

* TOC
{:toc}

Rocket Job ships with a set of ready-to-run jobs for common tasks: cleaning out old jobs, monitoring
directories for new files, copying and converting files, running ad-hoc Ruby code, and re-encrypting
data. They all live under the `RocketJob::Jobs` namespace and are themselves ordinary jobs, so they
can be scheduled, prioritized, retried, and managed through
[Mission Control](mission_control.html) like any other job.

This page covers each one, what it does, and how to create it. For the underlying concepts (fields,
state machine, scheduling, retries) see the [Programmer's Guide](guide.html); for parallel file
processing see the [Batch Guide](batch.html).

## Housekeeping Job

`RocketJob::Jobs::HousekeepingJob` removes old jobs so they do not accumulate and consume MongoDB
storage. This matters most for jobs that set `self.destroy_on_complete = false` (so they remain after
finishing) and for failed or aborted jobs, which are never destroyed automatically.

Retention is configured separately per state, so for example completed jobs can be cleaned up sooner
than failed jobs that may still need investigation. A retention of `nil` means "keep forever".

| State     | Default retention |
|:----------|:------------------|
| Aborted   | 7 days            |
| Completed | 7 days            |
| Failed    | 14 days           |
| Paused    | never (`nil`)     |
| Queued    | never (`nil`)     |

The job uses the [Cron](guide.html#scheduled-jobs) plugin and runs every 15 minutes. It is also a
singleton: only one instance can be queued or running at a time.

Create it with the defaults:

~~~ruby
RocketJob::Jobs::HousekeepingJob.create!
~~~

Create it with the default values shown explicitly, so they can be adjusted:

~~~ruby
RocketJob::Jobs::HousekeepingJob.create!(
  aborted_retention:   7.days,
  completed_retention: 7.days,
  failed_retention:    14.days,
  paused_retention:    nil,
  queued_retention:    nil
)
~~~

Remove aborted jobs after 1 day, completed jobs after 30 minutes, and never remove failed jobs:

~~~ruby
RocketJob::Jobs::HousekeepingJob.create!(
  aborted_retention:   1.day,
  completed_retention: 30.minutes,
  failed_retention:    nil
)
~~~

In addition to removing old jobs, the housekeeping job cleans up after servers that have died without
shutting down cleanly. When `destroy_zombies` is `true` (the default) it destroys zombie `Server`
records and requeues any jobs whose worker disappeared along with its server, so that work is not lost.
Set `destroy_zombies: false` to disable this.

~~~ruby
RocketJob::Jobs::HousekeepingJob.create!(destroy_zombies: false)
~~~

## Dirmon Job

`RocketJob::Jobs::DirmonJob` (Directory Monitor) watches one or more directories for new files and
starts a job to process each file as it arrives. It scans every 5 minutes by default, waits for each
file to stop growing before acting on it (so partially-uploaded files are not processed), and archives
files once handled.

Dirmon is driven by `RocketJob::DirmonEntry` records that describe what to watch and which job to
start. Because directory monitoring is a feature in its own right, with its own Mission Control
screens, it has a dedicated page: see the [Directory Monitoring guide](dirmon.html) for the full story.

Start Dirmon for the first time:

~~~ruby
RocketJob::Jobs::DirmonJob.create!
~~~

Dirmon is a singleton, so if an instance is already queued or running, `create!` raises:

~~~
Validation failed: State Another instance of this job is already queued or running
~~~

Use `create` (without the bang) to start it only if one is not already present:

~~~ruby
RocketJob::Jobs::DirmonJob.create
~~~

Change the scan interval by supplying a `cron_schedule`. To scan every minute instead of every 5:

~~~ruby
RocketJob::Jobs::DirmonJob.create!(cron_schedule: "*/1 * * * * UTC")
~~~

## Conversion Job

`RocketJob::Jobs::ConversionJob` converts a file from one tabular format to another: CSV, JSON, PSV,
and xlsx. It is a [batch](batch.html) job, so even very large files are converted in parallel across
workers. Compression and archive formats (`.gz`, `.zip`, and so on) are detected automatically from
the file name, and the source can be a local path or a remote URL.

Both the input and output categories use `format: :auto`, which infers the format from each file's
extension.

Convert a CSV file to JSON:

~~~ruby
job = RocketJob::Jobs::ConversionJob.new
job.input_category.file_name  = "data.csv"
job.output_category.file_name = "data.json"
job.save!
~~~

Convert JSON to PSV and compress the output with GZip:

~~~ruby
job = RocketJob::Jobs::ConversionJob.new
job.input_category.file_name  = "data.json"
job.output_category.file_name = "data.psv.gz"
job.save!
~~~

Read a zipped CSV file from a remote website and write a GZipped JSON file:

~~~ruby
job = RocketJob::Jobs::ConversionJob.new
job.input_category.file_name  = "https://example.org/file.zip"
job.output_category.file_name = "data.json.gz"
job.save!
~~~

## Copy File Job

`RocketJob::Jobs::CopyFileJob` copies a file from a source to a target, where each can be a local path,
a URL, or any location supported by [IOStreams](https://github.com/reidmorrison/iostreams) (SFTP, S3,
HTTP, and more). It is commonly used to push a finished output file to an SFTP server or object store.

Because it includes the [Retry](guide.html#automatic-retry) plugin, a failed copy is retried
automatically up to 10 times, which is useful given that remote transfers are prone to transient
failures.

Upload a file to an SFTP server:

~~~ruby
RocketJob::Jobs::CopyFileJob.create!(
  source_url:  "/exports/uploads/important.csv.pgp",
  target_url:  "sftp://sftp.example.org/uploads/important.csv.pgp",
  target_args: {
    username:    "Jack",
    password:    "OpenSesame",
    ssh_options: {
      IdentityFile: "~/.ssh/secondary"
    }
  }
)
~~~

The `source_streams` and `target_streams` options apply IOStreams transformations (such as
compression or encryption) on the way through, and `source_args` / `target_args` pass options to the
underlying source and target. When the Symmetric Encryption gem is installed, any argument whose key
starts with `encrypted_` is decrypted before use, and any whose key starts with `secret_config_` is
looked up via [Secret Config](https://config.rocketjob.io); the connection password is also stored
encrypted.

Instead of a `source_url`, raw data can be supplied directly with `source_data` (limited to about
15 MB after compression):

~~~ruby
RocketJob::Jobs::CopyFileJob.create!(
  source_data: "id,name\n1,Jack\n",
  target_url:  "s3://example-bucket/people.csv"
)
~~~

## Upload File Job

`RocketJob::Jobs::UploadFileJob` uploads a single file into another job and then starts that job. It is
the mechanism [Dirmon](dirmon.html) uses to feed an arriving file into the job that should process it,
but it can be used directly with any job class.

The target job must be a `RocketJob::Job` and must accept the file in one of three ways: by
implementing `#upload` (the usual case for batch jobs), or by having an `upload_file_name` or
`full_file_name` field that the path is assigned to.

~~~ruby
RocketJob::Jobs::UploadFileJob.create!(
  job_class_name:   "MyProcessFileJob",
  upload_file_name: "/incoming/orders.csv",
  properties:       {description: "Orders for today"}
)
~~~

`properties` is a hash of fields to set on the created job; each key must correspond to a writable
field on that job class, or validation fails. `original_file_name` can be supplied so the job sees the
original name (and its file extension, which drives format detection) even when the path on disk is a
temporary name. If anything goes wrong during the upload, the partially-populated downstream job is
cleaned up so no half-uploaded job is left behind.

## On Demand Job

`RocketJob::Jobs::OnDemandJob` runs a snippet of Ruby supplied as a string at create time, without
having to write and deploy a dedicated job class. It is ideal for one-off fixes, data cleanups, and
maintenance tasks that should run through the same queue, scheduling, and Mission Control machinery as
everything else.

The `code` field holds the Ruby to run; it is compiled into the job's `perform` method and validated
when the job is saved, so a syntax error is caught immediately rather than at run time. The job keeps
itself after completion (`destroy_on_complete = false`), and it includes the
[Cron](guide.html#scheduled-jobs) and [Retry](guide.html#automatic-retry) plugins.

Run some code once:

~~~ruby
code = <<~CODE
  User.unscoped.order("updated_at DESC").each do |user|
    user.cleanse_attributes!
    user.save!
  end
CODE

RocketJob::Jobs::OnDemandJob.create!(
  code:        code,
  description: "Cleanse users"
)
~~~

Test the code inline in a console before queuing it:

~~~ruby
job = RocketJob::Jobs::OnDemandJob.new(code: code, description: "cleanse users")
job.perform_now
~~~

Pass input data, available inside the code as the `data` hash. Use string keys only, not symbols:

~~~ruby
code = <<~CODE
  puts data["a"] * data["b"]
CODE

RocketJob::Jobs::OnDemandJob.create!(
  code: code,
  data: {"a" => 10, "b" => 2}
)
~~~

Retain a result by writing it back into `data`, which is persisted on the job:

~~~ruby
code = <<~CODE
  data["result"] = data["a"] * data["b"]
CODE

RocketJob::Jobs::OnDemandJob.create!(
  code: code,
  data: {"a" => 10, "b" => 2}
)
~~~

Schedule it to run nightly at 2am Eastern:

~~~ruby
RocketJob::Jobs::OnDemandJob.create!(
  cron_schedule: "0 2 * * * America/New_York",
  code:          code
)
~~~

Change the priority, description, or retry behavior like any other job:

~~~ruby
RocketJob::Jobs::OnDemandJob.create!(
  code:        code,
  description: "Cleanse users",
  priority:    30,
  retry_limit: 5
)
~~~

## On Demand Batch Job

`RocketJob::Jobs::OnDemandBatchJob` is the [batch](batch.html) counterpart to the On Demand Job: the
supplied `code` runs once per record, in parallel across workers. It is the standard tool for data
correction or cleansing over a large set of rows.

The `code` field is compiled into `perform(row)` and runs for every record. Optional `before_code` and
`after_code` fields run once, before and after the batch, and are typically used to upload the records
to process. As with `OnDemandJob`, all of the code is validated when the job is saved.

Upload an Active Record relation and process each row by its id. Uploading a relation automatically
sets `record_count`:

~~~ruby
code = <<~CODE
  if user = User.find(row)
    user.cleanse_attributes!
    user.save(validate: false)
  end
CODE

job = RocketJob::Jobs::OnDemandBatchJob.new(code: code, description: "cleanse users")
job.upload(User.unscoped.order("updated_at DESC"))
job.save!
~~~

Test against a subset directly in a console, then clean up the temporary slice collection:

~~~ruby
job = RocketJob::Jobs::OnDemandBatchJob.new(code: code, description: "cleanse users")
job.upload(User.unscoped.order("updated_at DESC").limit(100))
job.perform_now
job.cleanup!
~~~

Output is not collected by default. Call `#collect_output` to keep it, and set batch options such as
the [worker throttle](batch.html#throttling-concurrent-workers) and priority:

~~~ruby
job = RocketJob::Jobs::OnDemandBatchJob.new(
  description:              "Fix data",
  code:                     code,
  throttle_running_workers: 5,
  priority:                 30
)
job.collect_output
job.save!
~~~

Move the upload into `before_code` so the whole job, including how it loads its records, is described
in one `create!`:

~~~ruby
before_code = <<~CODE
  upload(User.unscoped.order("updated_at DESC"))
CODE

code = <<~CODE
  if user = User.find(row)
    user.cleanse_attributes!
    user.save(validate: false)
  end
CODE

RocketJob::Jobs::OnDemandBatchJob.create!(
  before_code: before_code,
  code:        code,
  description: "cleanse users"
)
~~~

`OnDemandBatchJob` also mixes in [Batch::Statistics](batch.html#gathering-statistics), so counters incremented in
the code are aggregated and visible on the completed job.

## Re-Encrypt Job

`RocketJob::Jobs::ReEncrypt::RelationalJob` re-encrypts every `encrypted_` column in a relational
database, rotating data to the current
[Symmetric Encryption](https://github.com/reidmorrison/symmetric-encryption) key. It is a batch job
that works directly against table and column names rather than models, so it covers tables whose
models have been removed and picks up new `encrypted_` columns automatically.

It is only defined when both Active Record and the `sync_attr` gem are available. Calling `start`
inspects the schema and queues one job per table that has encrypted columns:

~~~ruby
RocketJob::Jobs::ReEncrypt::RelationalJob.start
~~~

Because it discovers columns by name, any table with an `encrypted_` column is processed, including
temporary or non-application tables. Each table is processed in id ranges, and only values that change
under the new key are written back.

## Internal and testing jobs

A few jobs ship with Rocket Job for internal use and benchmarking rather than for direct use in an
application:

* `RocketJob::Jobs::ActiveJob` wraps an Active Job so it can run on Rocket Job through the Active Job
  adapter. It is not created directly.
* `RocketJob::Jobs::SimpleJob` and `RocketJob::Jobs::PerformanceJob` are no-op jobs (simple and batch,
  respectively) used to benchmark throughput. They are driven by `bin/rocketjob_perf` and
  `bin/rocketjob_batch_perf`.

---
layout: default
---

## Batch Jobs Guide
{:.no_toc}

**Contents**

* TOC
{:toc}

This guide covers batch jobs: jobs that process a large workload in parallel across many workers.
For the conventional single-worker job API (fields, scheduling, throttling, callbacks, queries), see
the [Programmer's Guide](guide.html).

## What is a batch job?

A regular [job](guide.html) runs on a single worker. A batch job breaks its input up into *slices*
so that many workers, often across hundreds of containers, process different parts of the work at
the same time.

Turn any job into a batch job by including `RocketJob::Batch` and writing a `perform` that handles a
single *record*:

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # Keep the job after it finishes so the output can be downloaded
  self.destroy_on_complete = false

  # Number of records per slice (the default)
  input_category slice_size: 100

  # Collect the value returned by each perform call as output
  output_category

  def perform(line)
    # Called once per record, spread across all available workers
    line.reverse
  end
end
~~~

A few terms:

* A **record** is one unit of work passed to `perform`. It is usually a line or row from a file, but
  can be any value that serializes to BSON (a String, Hash, Array, Integer, and so on).
* A **slice** is a group of records, 100 by default, that one worker claims and processes together.
* The job's input is uploaded into a dedicated MongoDB collection and divided into slices. For
  example, a 1,000,000 line file with the default `slice_size` of 100 becomes 10,000 slices.

Because the work is sliced, a batch job can be **paused, resumed, or aborted as a whole**, and if
any slices fail, all of them can be retried by retrying the job. A running batch job is also
**interrupted by a higher priority job**: low priority jobs use all available workers until more
important work arrives, then resume once it is done. See [Business Priority](guide.html#business-priority).

## Your first batch job

Using the `ReverseJob` above, queue some records for processing. The block form of `upload` hands you
a writer that you append records to one at a time:

~~~ruby
words = %w[these are some words to be processed across many workers]

job = ReverseJob.new
job.upload do |records|
  words.each { |word| records << word }
end
job.save!
~~~

Once the job completes, read the output (see [Collecting output](#collecting-output)):

~~~ruby
job.output.each do |slice|
  slice.each { |record| puts record }
end
~~~

## Uploading input data

Input data is uploaded into the job before it is saved. Rocket Job stores it in a MongoDB collection
unique to that job, and removes each slice as soon as it is processed. Failed slices stay in the
collection, marked as failed, holding the exception and the name of the worker that was processing
them.

Uploading the data into the job, rather than referencing an external file, has several benefits:

* Workers do not need shared access to the original file or data store.
* The file can be decompressed or decrypted once, up front, before it is sliced.
* No separate data store is needed to hold the job's input.
* Each slice has its own state, so it can fail independently and carry its own exception.

Data can be uploaded from a file, an Active Record query, a Mongoid query, an integer range, or a
block of code.

### Files

`upload` streams an entire file into the job, one record per line by default, and returns the number
of records uploaded. Very large files are streamed rather than loaded into memory, so files far
larger than RAM can be uploaded.

~~~ruby
job = ReverseJob.new
job.upload("myfile.txt")
job.save!
~~~

Rocket Job auto-detects compression and encryption from the file name and decodes it before slicing.
It has built-in support for:

* `Zip` files (add the `rubyzip` gem on CRuby; JRuby uses native Java Zip)
* `GZip` files
* files encrypted with [Symmetric Encryption](https://github.com/reidmorrison/symmetric-encryption)
* delimited files (Windows CR/LF or Linux LF line endings, auto-detected, or a custom delimiter)
* fixed-length record files

~~~ruby
# Auto-detected from the file extension:
job.upload("myfile.csv.zip")     # Zip
job.upload("myfile.csv.gz")      # GZip
job.upload("myfile.csv.zip.enc") # Encrypted Zip
~~~

Override the detected streams explicitly when the file name does not reflect the contents:

~~~ruby
job.upload("myfile.ze", streams: [:zip, :enc])
~~~

Useful `upload` keyword options:

| Option         | Description
|:---------------|:------------
| `category`     | Which input category to load into. Default: `:main`.
| `stream_mode`  | `:line` (default), `:array`, or `:hash`. See [input categories](#input-categories).
| `file_name`    | Override the file name used to infer format and streams.
| `delimiter`    | Record delimiter. Default: auto-detect line endings.
| `on_first`     | A lambda called with the first line, for example to capture a header.

By default all data is converted to UTF-8 before being stored, since MongoDB only stores UTF-8
strings. A Zip stream must contain only one file; the first file found is loaded. CSV and other
tabular parsing is deliberately left to the workers (see [Reading tabular files](#reading-tabular-files)),
so by default a file is uploaded a raw line at a time.

For the full list of supported file types and transformations, see
[IOStreams](https://github.com/reidmorrison/iostreams).

### Active Record queries

`upload_arel` uploads the result of an Active Record query. By default it uploads only the `:id` of
each row, adding it to the select list to reduce overhead:

~~~ruby
# Upload the ids of all US users
job.upload_arel(User.where(country_code: "US"))
~~~

Supply column names to upload more than the id:

~~~ruby
job.upload_arel(User.where(country_code: "US"), :user_name, :zip_code)
~~~

Pass a block to transform each model into the record to upload:

~~~ruby
job.upload_arel(User.where(country_code: "US")) { |user| user.email }
~~~

### Mongoid queries

`upload_mongo_query` uploads the result of a MongoDB query. It reads the collection directly, rather
than building a Mongoid model per document, to avoid that overhead:

~~~ruby
# Upload the ids of all users in Florida
job.upload_mongo_query(User.where(state: "FL"))

# Upload an additional field
job.upload_mongo_query(User.where(state: "FL"), :zip_code)
~~~

When a block is supplied it receives each document and returns the record to upload. The returned
value must serialize to BSON (`Hash`, `Array`, `String`, `Integer`, `Float`, `Symbol`, `Regexp`,
`Time`; not `Date`). With a `Hash`, keys must be strings, not symbols.

### Integer ranges

`upload_integer_range` uploads a range of integers efficiently, which is ideal for driving work off a
contiguous range of ids:

~~~ruby
job.upload_integer_range(1, 1_000_000)
~~~

`upload_integer_range_in_reverse_order` does the same but processes the highest ids first. A plain
`Range` can also be passed straight to `upload`:

~~~ruby
job.upload(1..1_000_000)
~~~

### A block

When `upload` is given a block, it yields a writer to which records are appended one at a time:

~~~ruby
job.upload do |writer|
  10.times { |i| writer << i }
end
~~~

## Input categories

The `input_category` class method configures how uploaded data is sliced and parsed. With no
arguments, a job has a single input category named `:main` with the defaults below.

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  input_category slice_size: 500, serializer: :compress

  def perform(record)
    # ...
  end
end
~~~

Input category options:

| Option             | Default     | Description
|:-------------------|:------------|:------------
| `name`             | `:main`     | Name of the category. Use additional names for secondary input collections.
| `slice_size`       | `100`       | Number of records per slice.
| `serializer`       | `:compress` | Slice serialization: `:none`, `:compress`, or `:encrypt`. See [Compression and encryption](#compression-and-encryption).
| `format`           | `nil`       | Parse each record before `perform`: `nil` (raw line), `:auto`, or a tabular format such as `:csv`. See [Reading tabular files](#reading-tabular-files).
| `format_options`   | `nil`       | Format-specific options, for example a `:layout` for `:fixed`.
| `columns`          | `nil`       | Header columns, when the file has no header row.
| `mode`             | `:line`     | How a file is uploaded: `:line`, `:array`, or `:hash`.
| `allowed_columns`  | `nil`       | Restrict tabular input to these columns; others are returned as nil.
| `required_columns` | `nil`       | Tabular columns that must be present, or an exception is raised.
| `skip_unknown`     | `false`     | When `allowed_columns` is set, ignore unknown columns instead of raising.
| `header_cleanser`  | `:default`  | Cleanse tabular header column names (`:default`) or leave them as-is (`:none`).

The `mode` option controls how a file is read during upload:

* `:line` (default) uploads a raw line (String) at a time. This is the most performant, since each
  worker parses its own lines.
* `:array` parses each line into an Array before uploading. The whole file is parsed up front, so an
  invalid file is detected before processing starts. Not recommended for very large files.
* `:hash` parses each line into a Hash before uploading. Like `:array`, but slightly less efficient.

## Collecting output

To keep the value returned by `perform`, register an output category with `output_category`. With no
arguments it registers a single output category named `:main`:

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  self.destroy_on_complete = false

  output_category

  def perform(line)
    line.reverse
  end
end
~~~

Read the collected output once the job has completed:

~~~ruby
job.output.each do |slice|
  slice.each { |record| puts record }
end
~~~

Or download it straight to a file, optionally compressed on the way out:

~~~ruby
job.download("reversed.txt.gz")
~~~

### Output ordering

The output slices and records are in exactly the same order as the records were uploaded, which
makes it easy to line an output record up with its input record. Two things change that alignment:

* An input file with a header row (for example CSV) whose output format does not have one (for
  example JSON) shifts every output record by one line.
* Setting `nils: false` on the output category (the default) skips records for which `perform`
  returned `nil`, so those positions are absent from the output.

### Waiting for completion

Output can be queried at any time, but it is only complete once the job has finished. To wait
programmatically:

~~~ruby
loop do
  sleep 1
  job.reload
  break unless job.running? || job.queued?
end
~~~

### Output categories

The `output_category` class method accepts these options:

| Option           | Default     | Description
|:-----------------|:------------|:------------
| `name`           | `:main`     | Name of the category. Register additional names for [multiple output files](#multiple-output-files).
| `serializer`     | `:compress` | Slice serialization: `:none`, `:compress`, `:encrypt`, `:bz2`, or `:encrypted_bz2`.
| `format`         | `nil`       | Render each result: `nil`, `:auto`, or a tabular format such as `:csv`. See [Writing tabular files](#writing-tabular-files).
| `format_options` | `nil`       | Format-specific options.
| `columns`        | `nil`       | Columns to include when rendering tabular output.
| `nils`           | `false`     | When `true`, store `nil` results too; when `false`, skip them.

### Multiple output files

A single batch job can write several output files by registering more than one output category and
returning categorized results from `perform`.

Use `RocketJob::Batch::Result` to direct a single value to a named category, and
`RocketJob::Batch::Results` to return several at once. `Result.new` takes the **category first, then
the value**:

~~~ruby
class MultiFileJob < RocketJob::Job
  include RocketJob::Batch

  self.destroy_on_complete = false

  # Default :main output category, plus an :invalid category
  output_category
  output_category(name: :invalid)

  def perform(line)
    if line.length < 10
      # Send short lines to the :invalid output collection
      RocketJob::Batch::Result.new(:invalid, line)
    else
      # Plain return values go to the :main output collection
      line.reverse
    end
  end
end
~~~

Download each category to its own file:

~~~ruby
job.download("reversed.txt.gz")
job.download("invalid.txt.gz", category: :invalid)
~~~

To write to several categories from a single `perform` call, collect them in a `Results`:

~~~ruby
def perform(row)
  outputs = RocketJob::Batch::Results.new
  outputs << {name: row["name"], age: row["age"]}                         # goes to :main
  outputs << RocketJob::Batch::Result.new(:zip_codes, {zip: row["zip"]})  # goes to :zip_codes
  outputs
end
~~~

## Reading tabular files

Received data is often tabular, like a spreadsheet, with a header row describing each column (CSV,
PSV, Excel, and so on). Set `format` on the `input_category` and Rocket Job parses each row just
before `perform` is called, passing in a `Hash` of header name to value instead of the raw line:

~~~ruby
class TabularJob < RocketJob::Job
  include RocketJob::Batch

  input_category format: :csv

  def perform(record)
    # record is a Hash, for example:
    # { "first_field" => 100, "second" => 200, "third" => 300 }
  end
end
~~~

~~~ruby
job = TabularJob.new
job.upload("my_really_big_csv_file.csv")
job.save!
~~~

CSV parsing is left to the workers, so the file still uploads a line at a time with minimal memory
overhead, even for very large files.

### Auto-detecting the file type

Set `format: :auto` to detect the format from the upload file name. The same unchanged job can then
process CSV, PSV, JSON, or xlsx files, as long as the column headers match:

~~~ruby
class TabularJob < RocketJob::Job
  include RocketJob::Batch

  input_category format: :auto

  def perform(record)
    # record is a Hash of header name => value
  end
end
~~~

~~~ruby
TabularJob.new.tap { |j| j.upload("really_big.csv") }.save!
TabularJob.new.tap { |j| j.upload("really_big.xlsx") }.save!
TabularJob.new.tap { |j| j.upload("really_big.json") }.save!
~~~

### Validating columns

When a tabular `input_category` has `allowed_columns`, `required_columns`, or `skip_unknown` set,
Rocket Job validates the header during upload, so a malformed file is rejected before any worker runs:

~~~ruby
input_category format:           :csv,
               allowed_columns:  %w[login last_login name state],
               required_columns: %w[login],
               skip_unknown:     true
~~~

## Writing tabular files

To produce a tabular output file, set `format` on the `output_category` and return a `Hash` from
`perform`. Rocket Job renders each hash into a line of the chosen format, and writes the header row
automatically:

~~~ruby
class ExportUsersJob < RocketJob::Job
  include RocketJob::Batch

  # Only these columns are written, in this order
  output_category format: :csv, columns: ["login", "last_login"]

  def perform(id)
    u = User.find(id)
    {"login" => u.login, "last_login" => u.updated_at}
  end
end
~~~

~~~ruby
job = ExportUsersJob.new
job.upload_arel(User.where(locked: true))
job.save!
# ... once complete ...
job.download("output.csv")
~~~

Sample `output.csv`:

~~~csv
login,last_login
jbloggs,2019-02-11 05:43:20
kadams,2019-01-12 01:20:20
~~~

### Filtering output columns

Rocket Job only writes the columns listed in `columns`, so `perform` can return a full attribute
hash and let the category select which columns to export. The same job can then export different
columns on different runs:

~~~ruby
class ExportUsersJob < RocketJob::Job
  include RocketJob::Batch

  output_category format: :csv, columns: ["login", "last_login"]

  def perform(login)
    # Return all attributes; only the configured columns are written
    User.find_by(login: login).attributes
  end
end
~~~

Override the columns per instance to widen or narrow the export:

~~~ruby
job = ExportUsersJob.new
job.output_category.columns = ["login", "last_login", "name", "state"]
job.save!
~~~

### Single output file via after_batch

The `after_batch` callback runs once, after all slices finish, which is a natural place to download
the assembled output file. This job parses a CSV input and writes a single CSV output:

~~~ruby
class TransformJob < RocketJob::Job
  include RocketJob::Batch

  self.destroy_on_complete = false

  input_category  format: :csv
  output_category format: :csv

  after_batch :download_file

  def perform(row)
    {
      name: "#{row['first_name'].downcase} #{row['last_name'].downcase}",
      age:  row["age"]
    }
  end

  def download_file
    download("names.csv")
  end
end
~~~

## Compression and encryption

Each category has a `serializer` that controls how its slices are stored. Compression reduces network
and disk usage, and is recommended for large jobs. As of Rocket Job v6 the default serializer is
`:compress`; set it to `:none` to disable.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  input_category  serializer: :compress
  output_category serializer: :compress

  def perform(line)
    line.reverse
  end
end
~~~

Set the serializer to `:encrypt` to encrypt slices at rest with
[Symmetric Encryption](https://github.com/reidmorrison/symmetric-encryption). Data is compressed
before being encrypted, to reduce the volume encrypted:

~~~ruby
input_category  serializer: :encrypt
output_category serializer: :encrypt
~~~

Output categories also support `:bz2` and `:encrypted_bz2` serializers.

### PGP encrypted output files

When exchanging files with another system, an open standard like PGP is ideal. Because `download`
accepts an [IOStreams](https://github.com/reidmorrison/iostreams) path, the output file can be PGP
encrypted for a recipient on the way out:

~~~ruby
class ExportJob < RocketJob::Job
  include RocketJob::Batch

  self.destroy_on_complete = false

  input_category  format: :csv
  output_category format: :csv

  field :pgp_public_key, type: String
  validates_presence_of :pgp_public_key

  after_batch :download_file

  def perform(row)
    {name: "#{row['first_name']} #{row['last_name']}", age: row["age"]}
  end

  def download_file
    path = IOStreams.path("names.csv")
    path.option(:pgp, import_and_trust_key: pgp_public_key)
    download(path)
  end
end
~~~

## Throttling concurrent workers

`throttle_running_workers` limits how many workers process slices of a single batch job instance at
once. Use it when too many concurrent workers would overwhelm a third party system or write too much
data too quickly to a primary database. It also lets several batch jobs run concurrently rather than
one job consuming every worker.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # No more than 10 workers on this job at a time
  self.throttle_running_workers = 10

  def perform(line)
    line.reverse
  end
end
~~~

This value can be changed at any time, even while the job runs, to raise or lower the worker count.
It is a soft limit: the number of active workers may briefly exceed or dip below it. `0` or `nil`
means no limit (the default).

### Custom batch throttles

Define custom throttles for batch jobs with `define_batch_throttle`. The named method receives the
slice and returns true when the throttle is exceeded, in which case the slice is left for later:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  # Do not process slices when the MySQL replica delay exceeds 5 minutes
  define_batch_throttle :mysql_throttle_exceeded?

  def perform(record)
    # ...
  end

  private

  def mysql_throttle_exceeded?(slice)
    status        = ActiveRecord::Base.connection.select_one("show slave status")
    seconds_delay = Hash(status)["Seconds_Behind_Master"].to_i
    seconds_delay >= 300
  end
end
~~~

### Processing windows

`RocketJob::Batch::ThrottleWindows` restricts when slices may be processed, which is useful for a
long-running job that should only run outside business hours. It supports up to two windows. The
windows only gate slice processing; the job can still start and finish at any time.

~~~ruby
class AfterHoursJob < RocketJob::Job
  include RocketJob::Batch
  include RocketJob::Batch::ThrottleWindows

  # Monday to Thursday, slices may run from 5pm Eastern for 15 hours (until 8am)
  self.primary_schedule = "0 17 * * 1-4 America/New_York"
  self.primary_duration = 15.hours

  # All weekend, starting Friday 5pm Eastern for 63 hours (until 8am Monday)
  self.secondary_schedule = "0 17 * * 5 America/New_York"
  self.secondary_duration = 63.hours

  def perform(record)
    # ...
  end
end
~~~

### Lowering priority for large jobs

`RocketJob::Batch::LowerPriority` automatically lowers a job's priority based on its `record_count`,
so that large jobs yield to smaller ones. Add `:lower_priority` as a `before_batch`, after the
`record_count` has been set (that is, after the data has been uploaded):

~~~ruby
class SampleJob < RocketJob::Job
  include RocketJob::Batch
  include RocketJob::Batch::LowerPriority

  before_batch :upload_data, :lower_priority

  def perform(record)
    record.reverse
  end

  private

  def upload_data
    upload { |stream| %w[abc def ghi].each { |r| stream << r } }
  end
end
~~~

## Error handling

Because a batch job is made of many slices, individual records can fail while others keep processing.
Inspect the exceptions on failed slices:

~~~ruby
job = RocketJob::Job.find("55bbce6b498e76424fa103e8")
job.input.each_failed_record do |record, slice|
  p slice.exception
end
~~~

Once every slice has either completed or failed, and only failed slices remain, the job as a whole is
marked `failed`. Retrying the job retries only the failed slices, so successfully processed records
are not reprocessed.

## Batch callbacks

In addition to the standard [job callbacks](guide.html#callbacks), batch jobs add callbacks at the
slice and batch level:

* `before_slice`, `after_slice`, `around_slice`: run on the worker, around each slice.
* `before_batch`, `after_batch`: run once for the whole job. They run asynchronously. `around_batch`
  is not supported.

`before_batch` is the place to upload data, and `after_batch` the place to download results or do
final bookkeeping, as shown in the [single output file](#single-output-file-via-after_batch) and
[lower priority](#lowering-priority-for-large-jobs) examples.

## Gathering statistics

`RocketJob::Batch::Statistics` lets a job count things while it runs and have those counts aggregated
across every slice and worker. It is the standard way to answer "how many records were valid, invalid,
or skipped?" without adding your own fields or a separate datastore.

Add the plugin and call `statistics_inc` inside `perform`:

~~~ruby
class ImportJob < RocketJob::Job
  include RocketJob::Batch
  include RocketJob::Batch::Statistics

  def perform(row)
    if row["email"].blank?
      statistics_inc("invalid")
      return
    end

    statistics_inc("imported")
    # ... import the row ...
  end
end
~~~

When the job completes, the totals are available in the `statistics` hash field:

~~~ruby
job.reload.statistics
# => {"imported" => 9_840, "invalid" => 160}
~~~

The counts are also included in the job's log entry when it completes or fails.

Increment by more than one by passing an amount, and increment several counters at once by passing a
hash:

~~~ruby
statistics_inc("rows", row.size)
statistics_inc("invalid" => 1, "skipped" => 1)
~~~

Keys may use dot notation to build nested counts, which is handy for grouping related categories:

~~~ruby
statistics_inc("invalid.missing_email")
statistics_inc("invalid.bad_country")
# => {"invalid" => {"missing_email" => 12, "bad_country" => 4}}
~~~

Statistics are committed per slice using an atomic MongoDB `$inc`, so thousands of workers can update
the same counters concurrently. Counts are gathered while a slice is processed and only saved for
records that complete successfully: if a `perform` raises an exception, the increments from that record
are discarded, so retrying a failed slice does not double-count.

The built-in [`OnDemandBatchJob`](jobs.html#on-demand-batch-job) already includes this plugin, so
`statistics_inc` is available in its `code` without any extra setup.

## Batch fields and status

Including `RocketJob::Batch` adds these fields:

| Field          | Description
|:---------------|:------------
| `record_count` | Total number of input records. Set automatically by `upload`. Until it is set, workers process slices but do not complete the job, which allows processing to begin while data is still uploading.
| `sub_state`    | Read-only. Breaks the `running` state into `:before`, `:processing`, `:after`, and `:complete`.

`percent_complete`, `worker_count`, and `worker_names` are all batch-aware. The `status` hash adds
slice-level counts (`queued_slices`, `active_slices`, `failed_slices`, `output_slices`) and, while
running, an estimated remaining duration:

~~~ruby
job.reload
job.status
# => {"active_slices" => 8, "failed_slices" => 0, "queued_slices" => 1200, ... }
~~~

## How batch jobs work

A batch job's input is uploaded into a MongoDB collection dedicated to that job and split into
slices. Each slice is an independent unit of work that any worker can claim with an atomic operation,
so thousands of workers across many servers process slices concurrently without colliding:

~~~
                          +-- worker -- slice 1 --+
   input file -- slices --+-- worker -- slice 2 --+-- output collection -- download
                          +-- worker -- slice N --+
~~~

Slices live in a separate MongoDB client (`rocketjob_slices`) from the jobs themselves. MongoDB's
ability to spill from memory to disk is what lets a single job hold millions of input and output
records without exhausting memory or needing a separate data store. Each slice carries its own state,
so a failure is isolated to that slice, retains its exception, and can be retried on its own.

## Next steps

* [Programmer's Guide](guide.html): the core job API that batch jobs build on.
* [Dirmon](dirmon.html): trigger batch jobs automatically when files arrive.
* [Mission Control](mission_control.html): watch slices and jobs run, and retry, pause, or abort them.
* [Included Jobs](jobs.html): ready-to-use jobs such as `OnDemandBatchJob`.

---
layout: default
title: Upgrading Rocket Job
description: >-
  The upgrade steps that need code or data changes when moving between
  versions, for v8, v7.1, v6 and v3, and why to upgrade one version at a time.
---

**Contents**

* TOC
{:toc}

Release notes for every version are published in the
[GitHub Releases](https://github.com/reidmorrison/rocketjob/releases). This page collects the
upgrade steps that need code or data changes when moving between versions.

## Upgrade one version at a time

Upgrade through each version in turn, such as from v7.0 to v7.1, and then to v8, rather than from
v7.0 straight to v8. After each upgrade, fix every deprecation warning that it reports before you
upgrade to the next version:

1. Upgrade to the next version, following its section below.
2. Run your tests with Ruby's deprecation warnings on, see
   [Find the deprecated options that you use](#find-the-deprecated-options-that-you-use), and
   change each line that a warning names, until none are left.
3. Change the saved documents that still hold a deprecated option, such as Dirmon entries, scheduled
   jobs and `UploadFileJob`s, since reading one back reports no warning.
4. Deploy, and only then upgrade to the next version.

A minor release, such as v7.1, adds what replaces the options that the next major release removes,
and deprecates them, so that each change can be made, and tested, while the old option still works.
The next major release, such as v8, then removes what was deprecated, so code that still uses it
stops working.

## Upgrading to v8

Upgrade to v7.1 first, and fix every deprecation warning that it reports, see
[Upgrading to v7.1](#upgrading-to-v71). v7.1 deprecates the category options that a schema replaces,
and runs on IOStreams 2.2 and Ruby 3.2, so those changes can be made, and tested, before v8 changes
Ruby, IOStreams and how files are read.

Rocket Job v8 requires IOStreams 3.0, and so Ruby 3.3 or later, which IOStreams 3.0 requires. On
JRuby that is JRuby 10.0 or later. Upgrade Ruby before upgrading Rocket Job.

Upgrade every server that runs workers at the same time, rather than running v7 and v8 workers
together. A v7 worker reads the jobs that v8 saves with the options that v7 has, such as
`format_options`, but ignores those that v8 adds, such as a category's `schema` or `encoding`.

### format_options is replaced by schema

A category's `format_options` is replaced by its `schema`, which IOStreams uses for every tabular
format, see [Typed values with a schema](batch.html#typed-values-with-a-schema). A fixed width
layout becomes a schema with the `width` of each field:

~~~ruby
# Before (deprecated)
input_category format:         :fixed,
               format_options: {
                 layout: [
                   {size: 10, key: "name"},
                   {size: 5, key: "zip", type: :integer}
                 ]
               }

# After
input_category format: :fixed,
               schema: {
                 "fieldsMatch" => "subset",
                 "fields"      => [
                   {"name" => "name", "type" => "string", "width" => 10, "truncate" => true},
                   {"name" => "zip", "type" => "integer", "width" => 5}
                 ]
               }
~~~

`IOStreams::Schema.from_layout(layout: ...)` returns the schema of a layout, with
`"fieldsMatch" => "subset"`, so that writing skips the keys of a record that the layout does not
list, as a layout did. Leave it out to raise `IOStreams::Errors::InvalidHeader` for such a key
instead, so that a misspelled key is not silently left out.

Check these when moving a layout to a schema:

* The keys of the records are the names of the fields, which are Strings, since MongoDB does not
  store Symbols. A layout with Symbol keys, such as `key: :name`, is saved with String keys, so a job
  that a worker reads back already gave records with String keys. Only a job that was not saved,
  such as one run with `perform_now`, gave records with Symbol keys, so change `record[:name]` to
  `record["name"]` in `#perform` if it reads them.
* The column options, such as `columns`, cannot be set with a schema. An input category's `columns`
  that narrowed the records of a layout to some of its keys become the fields of the schema. An
  output category's `columns` that named the values of an Array result are not needed when they
  are in the order of the fields, since an Array is written by the position of each field.

Existing jobs and settings keep working:

* `format_options` still works as it did before v8, since IOStreams reads a layout as it did,
  and the column options with it. It is deprecated, and will be removed.
* A job saved before v8 is read with its `format_options`, which are not changed when it is saved
  again, so its slices can still be processed by a v7 worker while servers are upgraded.
* A layout cannot be set with a schema, and one that is not valid raises
  `IOStreams::Errors::InvalidLayout` when it is set, rather than when a file is read.
* A job class that defines a category with `format_options`, and a Dirmon entry or an `UploadFileJob`
  that builds a job from properties that hold it, report a deprecation warning, see
  [Finding the deprecated options](#finding-the-deprecated-options).

### Column options are replaced by schema

The schema also describes the columns of a file, so the options that described them are deprecated,
as IOStreams 3.0 deprecates the options that they set: an input category's `allowed_columns`,
`required_columns`, `skip_unknown` and `header_cleanser`, and the `columns` of a file without a header
row, or of the output to write. See [Validating columns](batch.html#validating-columns) and
[Filtering output columns](batch.html#filtering-output-columns).

~~~ruby
# Before (deprecated)
input_category  format:           :csv,
                allowed_columns:  %w[login last_login name state],
                required_columns: %w[login],
                skip_unknown:     true
output_category format: :csv, columns: %w[login last_login]

# After
input_category  format: :csv,
                schema: {
                  "fieldsMatch" => "partial",
                  "fields"      => [
                    {"name" => "login", "constraints" => {"required" => true}, "allowBlank" => true},
                    {"name" => "last_login"},
                    {"name" => "name"},
                    {"name" => "state"}
                  ]
                }
output_category format: :csv,
                schema: {
                  "fieldsMatch" => "subset",
                  "fields"      => [
                    {"name" => "login"},
                    {"name" => "last_login"}
                  ]
                }
~~~

`"allowBlank" => true` keeps a record whose `login` is blank, as `required_columns` did, which only
checked that the file had the column. Leave it out to reject such a record too.

With a schema, the keys of each record are the names of its fields, and the columns of the header row
are matched to them whatever their case, spaces and punctuation, rather than cleansed. So a field
named `last_login` reads the column `Last Login`, and a field named `Last Login` keeps that key.
`fieldsMatch` defaults to `"exact"`: the columns must be the fields, in order, and a column that is not
a field raises `IOStreams::Errors::InvalidHeader`. Use `"subset"` or `"partial"` to skip the other
columns, as `skip_unknown: true` did.

Existing jobs and settings keep working:

* The deprecated options still work without a schema, as they did in v7, and will be removed. Two
  changes in the [changelog](https://github.com/reidmorrison/rocketjob/blob/main/CHANGELOG.md) apply
  to them too: `allowed_columns`, `required_columns` and `skip_unknown` now apply to every tabular
  input, such as JSON records, and a header row is cleansed as IOStreams 3.0 cleanses it, which keeps
  the letters that are not ASCII, so a column `Prénom` is `prénom` rather than `prnom`.
* v7 ignored `allowed_columns`, `required_columns` and `skip_unknown` for JSON records, for `columns`
  supplied for a file without a header row, and with `header_cleanser: :none`, so a job that relied on
  that may now fail records that it accepted. To get the v7 behavior back while such a job is changed,
  set `IOStreams.enforce_column_restrictions = false`, such as in an initializer. IOStreams 3.0
  deprecates it, and reports a deprecation warning when it is set while Ruby's deprecation warnings
  are on. To fix the job, describe its
  columns with a schema, or remove the options from it, since they never applied to its input.
* They cannot be set with a schema, and a category that sets both is not valid, since IOStreams would
  reject them rather than apply one and ignore the other. An input category's `columns` can still be
  set with a schema: `upload` sets them to the header row read from the file, as it is in the file,
  which the workers match to the fields.
* A job class that defines a category with one of them, and a Dirmon entry or an `UploadFileJob` that
  builds a job from properties that hold one, report a deprecation warning, see
  [Finding the deprecated options](#finding-the-deprecated-options).

### The :array upload mode is deprecated

An input category's `mode: :array`, and the `stream_mode: :array` of `upload`, are deprecated. Each
row that they upload is an Array, which only makes sense with the header row that the category
keeps. Use the default `:line` mode, in which each worker parses its lines, or `:hash`, which parses
the whole file when it is uploaded, so that a file with a problem is found before it is processed,
and uploads each record as a Hash that names its columns:

~~~ruby
# Before (deprecated)
input_category format: :csv, mode: :array

# After
input_category format: :csv, mode: :hash
~~~

`#perform` receives each record as a Hash in either mode, when the category has a format. Without a
format, `#perform` received each row as an Array, so set the category's format, such as `:csv`, and
change `#perform` to read the Hash.

### An input category holds the header row of one file

In the `:line` and `:array` modes an input category keeps the header row that `upload` read from a
file, and its workers read each line by it. Two cases changed, see
[More than one file](batch.html#more-than-one-file):

* Uploading a second file with a header row into the same input category raises `ArgumentError`, in
  any mode. v7 stored the second file's header row as a record, and read its lines with the first
  file's columns. Upload each file into its own input category, or upload every file in the `:hash`
  mode.
* The next run of a batch job that `RocketJob::Plugins::Cron` creates after the job uploaded its
  file, such as one with `cron_after_start: false`, whose next run is created when it completes or
  fails, reads the header row of its own upload. v7 copied the header row that the upload read into
  the next run, so each later run stored its file's header row as a record. A job saved by v7 does
  not record that its columns came from a file, so clear them once after upgrading, for each such
  scheduled job class, and again once the jobs of that class that were running when you upgraded
  have finished, since their next runs are copied from them:

  ~~~ruby
  MyScheduledJob.where(:state.in => %w[queued paused]).each do |job|
    # Skip an input category whose columns are set for a file without a header row.
    job.input_categories.each do |category|
      category.columns = nil
    end
    job.save!
  end
  ~~~

### A paused Singleton job is active

A job that includes `RocketJob::Plugins::Singleton` is not valid while another job of its class is
running, queued, or now also paused. The check runs whenever such a job is saved, not only when it is
created, so a queued job saved by v7 alongside a paused one of the same class fails the next time it
is saved, such as when a server starts it. Before upgrading, check each such class, and when it has
more than one, abort or destroy all but one of them:

~~~ruby
active = MySingletonJob.where(:state.in => %w[running queued paused]).to_a
if active.size > 1
  active.each do |job|
    puts "#{job.id} #{job.state}"
  end
end
~~~

### Finding the deprecated options

Rocket Job reports a Ruby deprecation warning for each deprecated category option that it is given,
naming the line of the job class that defines the category, or of the call to `upload` that supplies
one, such as `stream_mode: :array` or `allowed_columns:`, for example:

~~~
app/jobs/import_job.rb:5: warning: Rocket Job: allowed_columns:, skip_unknown: are deprecated, describe the columns of the file with schema: instead, see https://rocketjob.reidmorrison.com/upgrading.html
~~~

The warnings are only reported while Ruby's deprecation warnings are on, which they are in tests run
by Minitest, or with `ruby -W:deprecated` or `RUBYOPT=-W:deprecated`, so production stays quiet. A job
that was saved with a deprecated option, and is read back, does not report one. IOStreams reports its
own deprecation warnings for the options that it reads, which name a line of Rocket Job instead.

### Removed

These were deprecated or unused, and are removed in v8:

* `RocketJob::Plugins::Restart`, deprecated in v6. Use `RocketJob::Plugins::Cron`, see
  [Scheduled jobs](guide.html#scheduled-jobs).
* `RocketJob::LookupCollection`, which was not used by Rocket Job, and whose `upload` always raised
  `ArgumentError`.
* `#work_first_slice` of a batch job, deprecated in v6. In a `before_batch` callback, read the records
  of the first slice with `input.first` instead.
* The translation of batch jobs saved by v5 into v6 categories, when they are read. A job saved by
  v5, and never saved since by v6 or v7, cannot be read by v8: finish or destroy such jobs, or open
  and save them with v7, before upgrading.
* `upload_arel`, `upload_mongo_query`, `upload_integer_range` and
  `upload_integer_range_in_reverse_order` of a batch job, deprecated in v6. Call `upload` with the
  query or the range instead, with the columns to upload as `columns:`, see
  [Uploading input data](batch.html#uploading-input-data):

  ~~~ruby
  # Before
  job.upload_arel(User.where(country_code: "US"), :user_name, :zip_code)
  job.upload_mongo_query(User.where(state: "FL"), :zip_code)
  job.upload_integer_range(1, 1_000_000)
  job.upload_integer_range_in_reverse_order(1, 1_000_000)

  # After
  job.upload(User.where(country_code: "US"), columns: %i[user_name zip_code])
  job.upload(User.where(state: "FL"), columns: [:zip_code])
  job.upload(1..1_000_000)
  job.upload(1_000_000..1)
  ~~~

  A block passed to `upload_arel` or `upload_mongo_query` is passed to `upload` the same way. A range
  is uploaded in the direction it is written, so where `upload_integer_range(first, last)` was called
  with bounds that it computed, which uploaded nothing when `last` was less than `first`, check for
  that before calling `upload(first..last)`, which uploads the range in reverse instead. A range that
  excludes its end, such as `1...100`, does not upload it. The
  `before_code` of an `OnDemandBatchJob` that calls one of them, as its documentation showed, raises
  `NoMethodError` when the job runs: change it to call `upload`, including in the jobs that are already
  saved, such as a scheduled one, which copies its `before_code` to its next run.
* `upload_file_name` and `upload_file_name=` of a batch job, deprecated in v6, which read and set the
  `file_name` of its input category. Use the input category instead, such as
  `job.input_category.file_name = "orders.csv"`. The `upload_file_name` of an `UploadFileJob`, and a
  field of that name on a simple job, are not affected. Mission Control showed and logged it, so
  upgrade Mission Control to a release that supports v8.

## Upgrading to v7.1

v7.1 prepares an application for v8. It adds a category's `schema`, which replaces the options that
v8 removes, and reports a deprecation warning wherever the application uses one of those. Nothing
else changes: a job that does not use a schema reads and writes its files as it did in v7.0, and the
deprecated options keep working. The other pages of this site describe the latest release; the pages
for v7.1 are on its [v7 branch](https://github.com/reidmorrison/rocketjob/tree/v7/docs).

v7.1 requires IOStreams 2.2, which `bundle update rocketjob` installs. IOStreams 2.2 reports its own
deprecation warnings for what IOStreams 3.0, which v8 requires, removes, see
[Upgrading IOStreams to v2.2](https://iostreams.reidmorrison.com/upgrading.html#upgrading-to-v22).

Servers running v7.0 and v7.1 can run together, but upgrade every server before giving any job,
Dirmon entry or `UploadFileJob` a schema. A v7.0 worker ignores a category's schema, so it would read
the records of such a job by the header row as it is in the file, with every value as text.

### Replace format_options with a schema

A category's `format_options` is deprecated, and replaced by its `schema`, which IOStreams uses for
every tabular format, see [Typed values with a schema](batch.html#typed-values-with-a-schema). A
fixed width layout becomes a schema with the `width` of each field:

~~~ruby
# Before (deprecated)
input_category format:         :fixed,
               format_options: {
                 layout: [
                   {size: 10, key: "name"},
                   {size: 5, key: "zip", type: :integer}
                 ]
               }

# After
input_category format: :fixed,
               schema: {
                 "fieldsMatch" => "subset",
                 "fields"      => [
                   {"name" => "name", "type" => "string", "width" => 10, "truncate" => true},
                   {"name" => "zip", "type" => "integer", "width" => 5}
                 ]
               }
~~~

Each column of the layout is a field of the schema: its `key` is the `name`, its `size` the
`width`, and its `type` the `type`, with `"truncate" => true` on a `string` field, as a layout
truncates a longer value. The table in IOStreams'
[Moving a layout to a schema](https://iostreams.reidmorrison.com/upgrading.html#moving-a-layout-to-a-schema)
gives each of them, including fillers and `:float`. `"fieldsMatch" => "subset"` makes writing skip
the keys of a record that the layout does not list, as a layout did. Leave it out to raise
`IOStreams::Errors::InvalidHeader` for such a key instead, so that a misspelled key is not silently
left out.

A schema reads a fixed width file differently from a layout, so check each job as you move it:

* The keys of the records are the names of the fields, which are Strings, since MongoDB does not
  store Symbols. A layout with Symbol keys, such as `key: :name`, is saved with String keys, so a job
  that a worker reads back already gave records with String keys. Only a job that was not saved,
  such as one run with `perform_now`, gave records with Symbol keys, so change `record[:name]` to
  `record["name"]` in `#perform` if it reads them.
* A value that is not of the type of its field, such as letters in an `integer` field, fails its
  record with `IOStreams::Errors::InvalidValue`.
* The text is read as UTF-8, see [Text is read as UTF-8 with a schema](#text-is-read-as-utf-8-with-a-schema).
* The column options, such as `columns`, cannot be set with a schema. An input category's `columns`
  that narrowed the records of a layout to some of its keys become the fields of the schema.

A layout cannot be set with a schema, since IOStreams would reject them rather than apply one and
ignore the other.

### Replace the column options with a schema

The schema also describes the columns of a file, so the options that described them are deprecated:
an input category's `allowed_columns`, `required_columns`, `skip_unknown` and `header_cleanser`, and the
`columns` of a file without a header row, or of the output to write. So are the same options passed
to `upload`, such as `allowed_columns:`. See [Validating columns](batch.html#validating-columns) and
[Filtering output columns](batch.html#filtering-output-columns).

~~~ruby
# Before (deprecated)
input_category  format:           :csv,
                allowed_columns:  %w[login last_login name state],
                required_columns: %w[login],
                skip_unknown:     true
output_category format: :csv, columns: %w[login last_login]

# After
input_category  format: :csv,
                schema: {
                  "fieldsMatch" => "partial",
                  "fields"      => [
                    {"name" => "login", "constraints" => {"required" => true}, "allowBlank" => true},
                    {"name" => "last_login"},
                    {"name" => "name"},
                    {"name" => "state"}
                  ]
                }
output_category format: :csv,
                schema: {
                  "fieldsMatch" => "subset",
                  "fields"      => [
                    {"name" => "login"},
                    {"name" => "last_login"}
                  ]
                }
~~~

`"allowBlank" => true` keeps a record whose `login` is blank, as `required_columns` did, which only
checked that the file had the column. Leave it out to reject such a record too.

With a schema, the keys of each record are the names of its fields, and the columns of the header row
are matched to them whatever their case, spaces and punctuation, rather than cleansed. So a field
named `last_login` reads the column `Last Login`, and a field named `Last Login` keeps that key.
`fieldsMatch` defaults to `"exact"`: the columns must be the fields, in order, and a column that is not
a field raises `IOStreams::Errors::InvalidHeader`. Use `"subset"` or `"partial"` to skip the other
columns, as `skip_unknown: true` did. See
[Moving the column options to a schema](https://iostreams.reidmorrison.com/upgrading.html#moving-the-column-options-to-a-schema).

The deprecated options cannot be set with a schema, and a category that sets both is not valid. An
input category's `columns` can still be set with a schema, and are not deprecated with one: `upload`
sets them to the header row read from the file, as it is in the file, which the workers match to the
fields.

### Replace the :array upload mode

An input category's `mode: :array`, and the `stream_mode: :array` of `upload`, are deprecated, and
cannot be used with a schema. Use the default `:line` mode, in which each worker parses its lines, or
`:hash`, which parses the whole file when it is uploaded, so that a file with a problem is found before
it is processed:

~~~ruby
# Before (deprecated)
input_category format: :csv, mode: :array

# After
input_category format: :csv, mode: :hash
~~~

With a schema, both modes upload the lines of the file, so that `#perform` receives each value as its
type, such as a `Date`.

### Text is read as UTF-8 with a schema

The text of a file uploaded into a category with a schema is read as UTF-8, so letters that are not
ASCII, such as `José`, are kept, and text that is not valid UTF-8 raises
`IOStreams::Errors::InvalidEncoding`, and uploads nothing. Without a schema, a tabular upload still
removes every character that is not ASCII, as in v7.0, so moving a job to a schema keeps letters that
it used to lose. An encoding set on the path that is uploaded is used instead.

### Find the deprecated options that you use

Rocket Job reports a Ruby deprecation warning for each deprecated category option that it is given,
naming the line of the job class that defines the category, or of the call to `upload` that supplies
one, such as `stream_mode: :array` or `allowed_columns:`, for example:

~~~
app/jobs/import_job.rb:5: warning: Rocket Job: allowed_columns:, skip_unknown: are deprecated, describe the columns of the file with schema: instead, see https://rocketjob.reidmorrison.com/upgrading.html#upgrading-to-v71
~~~

A Dirmon entry or an `UploadFileJob` whose properties hold a deprecated option reports one when it
builds its job, without the line of a job class.

The warnings are only reported while Ruby's deprecation warnings are on, which they are in tests run
by Minitest, or with `ruby -W:deprecated` or `RUBYOPT=-W:deprecated`, so production stays quiet. A job
that was saved with a deprecated option, and is read back, does not report one. IOStreams reports its
own deprecation warnings, prefixed `IOStreams:`, for the methods and options that the application
calls on it.

## Upgrading to v6

- Support for Ruby v3 and Rails 6.
- Major enhancements in Batch job support:
    - Direct built-in Tabular support for all input and output categories.
    - Multiple output file support, each with its own settings for:
        - Compression: GZip, Zip, BZip2 (chunked for much faster loading into Apache Spark).
        - Encryption: PGP, Symmetric Encryption.
        - File format: CSV, PSV, JSON, Fixed Format, xlsx.
- Significant error handling improvements, especially around throttle failures that used to result
  in "hanging" jobs.
- Removed use of Symbols to meet the Symbol deprecation in MongoDB and Mongoid.

### Deprecated Tabular plugins

The following plugins have been deprecated and are no longer loaded by default.

- `RocketJob::Batch::Tabular::Input`
- `RocketJob::Batch::Tabular::Output`

If your code relies on these plugins and you still want to upgrade to Rocket Job v6, add the
following require statement to any jobs that still use them:

~~~ruby
require "rocket_job/batch/tabular"
~~~

It is important to migrate away from these plugins, since they will be removed in a future release.

### Scheduled jobs

For any scheduled jobs that include the `RocketJob::Plugins::Cron` plugin, the default behavior has
changed so that the scheduled job instance is created immediately after the currently scheduled
instance starts.

To maintain the old behavior of creating the job when it fails, aborts, or completes, add the
following line to each of the applicable jobs:

~~~ruby
self.cron_after_start = false
~~~

Additionally, scheduled jobs now prevent a new one from being created when another scheduled
instance of the same job is already queued, or running with the _same_ `cron_schedule`.

To maintain the old behavior of allowing multiple instances with the same cron schedule, add the
following line to each of the applicable jobs:

~~~ruby
self.cron_singleton = false
~~~

Since scheduled jobs now implement their own singleton logic, remove the singleton plugin from any
scheduled jobs.

### Batch jobs

Rocket Job v6 replaces the array of symbols for `input_categories` and `output_categories` with an
array of `RocketJob::Category::Input` and `RocketJob::Category::Output`.

Jobs that added or modified the input or output categories need to be upgraded. For example:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  self.output_categories = [:main, :errors, :ignored]
end
~~~

Needs to be changed to:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  output_category name: :main
  output_category name: :errors
  output_category name: :ignored
end
~~~

#### slice_size, encrypt, compress

These fields have been removed from the job itself:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  self.slice_size = 1_000
  self.encrypt    = true
  self.compress   = true
end
~~~

They are now specified on the `input_category` as follows:

- `slice_size` just moves under `input_category`.
- `encrypt` becomes an option to `serializer`.
- `compress` is now the default for all batch jobs, so it is not needed.

If the serializer is set to `encrypt` then it is automatically compressed.

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  input_category slice_size: 1_000, serializer: :encrypt
end
~~~

#### collect_output, collect_nil_output

The following fields have been moved from the job itself:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  self.collect_output     = true
  self.collect_nil_output = true
end
~~~

Into the corresponding `output_category`:

- `collect_output` no longer has any meaning. Output is collected anytime an `output_category` is
  defined.
- `collect_nil_output` is now the option `nils` on the `output_category`. It defaults to `false` so
  that by default any `nil` output from the `perform` method is not collected.

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  output_category nils: true
end
~~~

#### Category name

For both `input_category` and `output_category`, when the `name` argument is not supplied it
defaults to `:main`. For example:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  input_category name: :main, serializer: :encrypt
  output_category name: :main
end
~~~

Is the same as:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  input_category serializer: :encrypt
  output_category
end
~~~

#### Existing and in-flight jobs

When migrating to Rocket Job v6, it is recommended to load every job and then save it back again as
part of the deployment. When the job loads it will automatically convert itself from the old schema
to the new v6 schema.

In-flight jobs should not be affected, other than it is important to shut down all running batch
servers _before_ running any new instances.

## Upgrading to v3

V3 replaces MongoMapper with Mongoid, which supports the latest MongoDB Ruby client driver.

### Mongo config file

Replace `mongo.yml` with `mongoid.yml`. Start with the sample
[mongoid.yml](https://github.com/reidmorrison/rocketjob/blob/main/test/config/mongoid.yml).

Note: the `rocketjob` and `rocketjob_slices` clients in the above `mongoid.yml` file are both
required.

### Other changes

Arguments are no longer supported. Use fields for defining all named arguments for a job.

Replace usages of `rocket_job do` to set default values:

~~~ruby
rocket_job do |job|
  job.priority = 25
end
~~~

With:

~~~ruby
self.priority = 25
~~~

Replace `key` with `field` when adding attributes to a job:

~~~ruby
key :inquiry_defaults, Hash
~~~

With:

~~~ruby
field :inquiry_defaults, type: Hash, default: {}
~~~

Replace usage of `public_rocket_job_properties` with the `user_editable` option:

~~~ruby
field :priority, type: Integer, default: 50, user_editable: true
~~~

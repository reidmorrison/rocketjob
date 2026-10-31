---
layout: default
title: Upgrading Rocket Job
description: >-
  The upgrade steps that need code or data changes when moving between
  versions, for v7.1, v6 and v3, and why to upgrade one version at a time.
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
   change what each warning reports, until none are left.
3. Change the saved documents that still hold a deprecated option, such as Dirmon entries, scheduled
   jobs and `UploadFileJob`s, since reading one back reports no warning.
4. Deploy, and only then upgrade to the next version.

A minor release, such as v7.1, adds what replaces the options that the next major release removes,
and deprecates them, so that each change can be made, and tested, while the old option still works.
The next major release, such as v8, then removes what was deprecated, so code that still uses it
stops working.

## Upgrading to v7.1

v7.1 moves Rocket Job to IOStreams 2.2, which `bundle update rocketjob` installs. IOStreams 2.2
deprecates what IOStreams 3.0 removes, and reports a deprecation warning wherever the application uses
one of those, see
[Upgrading IOStreams to v2.2](https://iostreams.reidmorrison.com/upgrading.html#upgrading-to-v22).
Rocket Job 7.1 no longer uses any of them itself.

An application sets some of them through Rocket Job, rather than on IOStreams: a category's
`format_options`, and the options that describe the columns of a file, such as `allowed_columns`.
IOStreams does not report those that a category passes to it, so Rocket Job reports them instead, and
adds a category's `schema`, which replaces them, as IOStreams' `#schema` replaces them. The deprecated
options keep working.

A job that does not use a schema reads and writes its files as it did in v7.0, apart from these
fixes:

* An upload of a path whose streams were set with `#stream`, such as `stream(:gz)`, into a category
  with a format reads the file, where v7.0 raised or read the wrong text.
* Blank lines before the header row of a tabular file are skipped, where v7.0 took the first one as
  the header row.
* A `format: :auto` upload of a JSON or fixed width file keeps its first record, so `record_count` is
  one more than in v7.0.
* A category in the `:array` or `:hash` mode reads the header row of a file such as CSV, where v7.0
  raised, or failed every slice.

Servers running v7.0 and v7.1 can run together, but upgrade every server before giving any job,
Dirmon entry or `UploadFileJob` a schema. A v7.0 worker ignores a category's schema, so it would read
the records of such a job by the header row as it is in the file, with every value as text.

### Replace format_options with a schema

A category's `format_options` is deprecated, and replaced by its `schema`, which IOStreams uses for
every tabular format, see [Describing a file with a schema](batch.html#typed-values-with-a-schema). A
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

* The keys of the records are the names of the fields, which are Strings. A layout with Symbol keys,
  such as `key: :name`, gave records with Symbol keys, also once a worker read the job back, so add
  `"keyType" => "symbol"` to its schema to keep them, or change `record[:name]` to `record["name"]`
  in `#perform`.
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
to `upload`, such as `allowed_columns:`. See
[Matching columns to the fields of a schema](batch.html#matching-columns-to-the-fields-of-a-schema)
and [Filtering output columns](batch.html#filtering-output-columns).

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

The schema property that replaces each option, and each combination of them:

| Option                                      | With a schema
|:--------------------------------------------|:-------------
| `header_cleanser: :default`, the default    | `"keyType" => "cleansed"`, so that the keys of each record are cleansed, as before. A column that is not a field, which `"extraColumns" => "keep"` keeps, is keyed the same way.
| `allowed_columns`                           | `"fieldsMatch" => "superset"`, which accepts a file without some of the fields, as `allowed_columns` does, or `"equal"` when `required_columns` lists every allowed column.
| `allowed_columns` with `skip_unknown: true` | `"fieldsMatch" => "partial"`, which accepts a file without some of the fields, as `allowed_columns` does, or `"subset"` when `required_columns` lists every allowed column.
| `required_columns` with `allowed_columns`   | `"constraints" => {"required" => true}` with `"allowBlank" => true` on each required field, which needs the column but not a value, as `required_columns` did. Without `allowBlank`, a blank value raises too.
| `required_columns` alone                    | A field for each of them, with `"constraints" => {"required" => true}` and `"allowBlank" => true`, and `"fieldsMatch" => "subset"` with `"extraColumns" => "keep"`, which keeps the other columns of the file, after the fields, as `required_columns` did. Add `"keyType" => "cleansed"` to keep their keys cleansed, such as `last_login` for the column `Last Login`: without it they are keyed as they are in the file, so `record["last_login"]` is nil, without an error.
| `header_cleanser: :none`                    | `"fieldsMatch" => "subset"`, `"extraColumns" => "keep"` and `"fields" => []`, which keeps every column, named as it is in the file, without `keyType`.
| `columns`, for a file without a header row  | `"header" => false`, with a field for each column, in order, named as the column was, without `keyType`. A `nil` column is a field with `"skip" => true`, which holds its place.
| `format_options` with a fixed width layout  | The `width` of each field, and `"keyType" => "symbol"` when the keys of the layout are Symbols.

7.0 did not apply `allowed_columns`, `required_columns` or `skip_unknown` in three cases, so leave them
out of the schema there, rather than describe them, or the schema starts rejecting or dropping columns
that 7.0 kept:

* to JSON records, which keep every key, as they are named,
* to `columns` supplied for a file without a header row, and
* with `header_cleanser: :none`.

With `format: :auto` they applied to a CSV or PSV file but not to a JSON file, which one schema cannot
do, so choose what each kind of file needs.

A schema keeps the letters that are not ASCII in a column's name, where 7.0 removed them, so rename a
field such as `prnom`, for the column `Prénom`, to `prénom`. Otherwise `"partial"`, `"subset"` and
`"superset"` skip that column without an error.

Before applying a schema to a job, read a recent file of the job with it, and compare the records
with those that the job receives now.

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

### Upload modes with a schema

A category with a schema cannot use the `:array` mode, nor be uploaded with `stream_mode: :array`.
Use the default `:line` mode, in which each worker parses its lines, or `:hash` to also parse every
line when the file is uploaded, so that a file with a problem is found before it is processed. Both
upload the lines of the file, so that `#perform` receives each value as its type, such as a `Date`.

Without a schema, a category's `mode` does not change how a file is uploaded: its lines are uploaded.
`stream_mode: :array` still parses each line into an Array, as in v7.0, except that IOStreams 2.2
deprecates reading a JSON file as Arrays. For an upload of a JSON file with `stream_mode: :array`,
IOStreams reports `each(:array)` as deprecated at a line of Rocket Job (`category/input.rb`), not of
your application: use `stream_mode: :hash`, which uploads the same Hashes.

### Text is read as UTF-8 with a schema

The text of a file uploaded into a category with a schema is read as UTF-8, so letters that are not
ASCII, such as `José`, are kept, and text that is not valid UTF-8 raises
`IOStreams::Errors::InvalidEncoding`, and uploads nothing. Without a schema, a tabular upload still
removes every character that is not ASCII, as in v7.0, so moving a job to a schema keeps letters that
it used to lose. An encoding set on the path that is uploaded is used instead.

### Find the deprecated options that you use

Rocket Job reports a Ruby deprecation warning for each deprecated category option that it is given,
naming the line of the job class that defines the category, or of the call to `upload` that supplies
one, such as `allowed_columns:`, for example:

~~~
app/jobs/import_job.rb:5: warning: Rocket Job: allowed_columns:, skip_unknown: are deprecated, describe the columns of the file with schema: instead, see https://rocketjob.reidmorrison.com/upgrading.html#upgrading-to-v71
~~~

A Dirmon entry or an `UploadFileJob` whose properties hold a deprecated option reports one when it
builds its job, without the line of a job class.

An option passed to `upload`, such as `allowed_columns:`, is reported twice: by Rocket Job, at the
line that calls `upload`, and by IOStreams, since Rocket Job passes it on. Change the call to `upload`
that Rocket Job's warning names.

IOStreams also reports what Rocket Job passes on from a call to `upload` or `download`, such as a
deprecated form of a path, like `job.upload("~/in.csv")`, or a JSON file uploaded with
`stream_mode: :array`, see [Upload modes with a schema](#upload-modes-with-a-schema). Such a warning
names a line of Rocket Job, such as `lib/rocket_job/category/input.rb`, rather than of your
application, so find the call to `upload` or `download` that supplied it, and change that.

The warnings are only reported while Ruby's deprecation warnings are on, which they are in tests run
by Minitest, or with `ruby -W:deprecated` or `RUBYOPT=-W:deprecated`, so production stays quiet. A job
that was saved with a deprecated option, and is read back, does not report one. IOStreams reports its
own deprecation warnings, prefixed `IOStreams:`, for the methods and options that the application
calls on it.

### Check the paths and stream options saved in the database

IOStreams 2.2 also deprecates some forms of paths and stream options, such as a local file name that
starts with `~/`, see
[Deprecated, and what replaces it](https://iostreams.reidmorrison.com/upgrading.html#deprecated-and-what-replaces-it).
IOStreams reports one only when the path is used, so tests seldom report those that are saved in the
database. Rocket Job passes these to IOStreams:

* the `pattern` and `archive_directory` of each Dirmon entry, and the paths in its `properties`,
* the `source_url`, `target_url`, arguments and streams of each `CopyFileJob`,
* the `upload_file_name` and `original_file_name` of each `UploadFileJob`,
* the `file_name` of each category of a batch job, and
* each field of your own of type `IOStreams::Path`.

To have IOStreams report most of them, run this in a console of the application, such as
`bin/rails console`. It reads each Dirmon entry and job, and builds its paths without opening them:

~~~ruby
Warning[:deprecated] = true

RocketJob::DirmonEntry.each do |entry|
  puts "Dirmon entry #{entry.name}:"
  IOStreams.path(entry.pattern)
  IOStreams.path(entry.archive_directory) if entry.archive_directory.present?
end

RocketJob::Job.each do |job|
  puts "#{job.class.name} #{job.id}:"
  case job
  when RocketJob::Jobs::CopyFileJob
    job.source_path if job.source_url
    job.target_path
  when RocketJob::Jobs::UploadFileJob
    job.upload_file_name
  when RocketJob::Batch
    job.input_categories.each(&:file_name)
    job.output_categories.each(&:file_name)
  end
end
~~~

Each warning follows the name of the Dirmon entry or job that holds the path. Check the paths in the
`properties` of Dirmon entries, the `original_file_name` of each `UploadFileJob`, and your own fields
by hand.

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

---
layout: default
title: Upgrading Rocket Job
description: >-
  The upgrade steps that need code or data changes when moving between major
  versions, for v8, v6 and v3.
---

**Contents**

* TOC
{:toc}

Release notes for every version are published in the
[GitHub Releases](https://github.com/reidmorrison/rocketjob/releases). This page collects the
upgrade steps that need code or data changes when moving between major versions.

## Upgrading to v8

### format_options is replaced by schema

A category's `format_options` is replaced by its `schema`, which IOStreams uses for every tabular
format, see [Typed values with a schema](batch.html#typed-values-with-a-schema). A fixed width
layout becomes a schema with the `width` of each field:

~~~ruby
# Before (deprecated)
input_category format:         :fixed,
               format_options: {layout: [{size: 10, key: "name"}, {size: 5, key: "zip", type: :integer}]}

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
  store Symbols. A layout with Symbol keys, such as `key: :name`, gave records with Symbol keys, so
  change `record[:name]` to `record["name"]` in `#perform`.
* The column options, such as `columns`, cannot be set with a schema. An input category's `columns`
  that narrowed the records of a layout to some of its keys become the fields of the schema. An
  output category's `columns` that named the values of an Array result are not needed when they
  are in the order of the fields, since an Array is written by the position of each field.

Existing jobs and settings keep working:

* `format_options` still works as it did before v8, since IOStreams reads a layout as it did,
  including its Symbol keys, and the column options with it. It is deprecated, and will be removed.
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
                schema: {"fieldsMatch" => "subset", "fields" => [{"name" => "login"}, {"name" => "last_login"}]}
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

* The deprecated options still work without a schema, as they did in v7, and will be removed.
* They cannot be set with a schema, and a category that sets both is not valid, since IOStreams would
  reject them rather than apply one and ignore the other. An input category's `columns` can still be
  set with a schema: `upload` sets them to the header row read from the file, as it is in the file,
  which the workers match to the fields.
* A job class that defines a category with one of them, and a Dirmon entry or an `UploadFileJob` that
  builds a job from properties that hold one, report a deprecation warning, see
  [Finding the deprecated options](#finding-the-deprecated-options).

### Finding the deprecated options

Rocket Job reports a Ruby deprecation warning for each deprecated category option that it is given,
naming the line of the job class that defines the category, for example:

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

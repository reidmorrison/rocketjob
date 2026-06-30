---
layout: default
---

## Upgrading Rocket Job
{:.no_toc}

**Contents**

* TOC
{:toc}

Release notes for every version are published in the
[GitHub Releases](https://github.com/reidmorrison/rocketjob/releases). This page collects the
upgrade steps that need code or data changes when moving between major versions.

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
[mongoid.yml](https://github.com/reidmorrison/rocketjob/blob/master/test/config/mongoid.yml).

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

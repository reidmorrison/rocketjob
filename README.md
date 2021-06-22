# Rocket Job
[![Gem Version](https://img.shields.io/gem/v/rocketjob.svg)](https://rubygems.org/gems/rocketjob) [![Downloads](https://img.shields.io/gem/dt/rocketjob.svg)](https://rubygems.org/gems/rocketjob) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg) [![Support](https://img.shields.io/badge/IRC%20(gitter)-Support-brightgreen.svg)](https://gitter.im/rocketjob/support)

Ruby's missing batch system

Checkout https://rocketjob.io/

![Rocket Job](https://rocketjob.io/images/rocket/rocket-icon-512x512.png)

## Documentation

* [Guide](http://rocketjob.io/)
* [API Reference](http://www.rubydoc.info/gems/rocketjob/)

## Support

* Questions? Join the chat room on Gitter for [rocketjob support](https://gitter.im/rocketjob/support)
* [Report bugs](https://github.com/rocketjob/rocketjob/issues)

## Rocket Job v6

- Support for Ruby v3 and Rails 6.
- Major enhancements in Batch job support:
    - Direct built-in Tabular support for all input and output categories.
    - Multiple output file support, each with its own settings for:
        - Compression
            - GZip, Zip, BZip2 (Chunked for much faster loading into Apache Spark).
        - Encryption
            - PGP, Symmetric Encryption.
        - File format
            - CSV, PSV, JSON, Fixed Format, xlsx.
- Significant error handling improvements, especially around throttle failures
  that used to result in "hanging" jobs.
- Support AWS DocumentDB in addition to MongoDB as the data store.
- Removed use of Symbols to meet Symbol deprecation in MongoDB and Mongoid.

### Upgrading to Rocket Job v6

The following plugins have been deprecated and are no longer loaded by default.
- `RocketJob::Batch::Tabular::Input`
- `RocketJob::Batch::Tabular::Output`

If your code relies on these plugins and you still want to upgrade to Rocket Job v6,
add the following require statement to any jobs that still use them:

~~~ruby
require "rocket_job/batch/tabular"
~~~

It is important to migrate away from these plugins, since they will be removed in a future release.

#### Upgrading Batch Jobs to Rocket Job v6

Rocket Job v6 replaces the array of symbol type for `input_categories` and `output_categories`
with an array of `RocketJob::Category::Input` and `RocketJob::Category::Output`.

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

##### slice_size, encrypt, compress

These fields have been removed from the job itself:
~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch
  
  self.slice_sice = 1_000
  self.encrypt    = true
  self.compress   = true
end
~~~

They are now specified on the `input_category` as follows:
- `slice_size` just moves under `input_category`. 
- `encrypt` becomes an option to `serializer`.
- `compress` is now the default for all batch jobs so is not needed.

If the serializer is set to `encrypt` then it is automatically compressed.

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch
  
  input_category slice_sice: 1_000, serializer: :encrypt
end
~~~

##### collect_output, collect_nil_output

The following fields have been moved from the job itself:
~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch
  
  self.collect_output     = true
  self.collect_nil_output = true
end
~~~

Into the corresponding `output_category`:
- `collect_output` no longer has any meaning. Output is collected anytime an `output_category` is defined.
- `collect_nil_output` is now the option `nils` on the `output_category. 
  It defaults to `false` so that by default any `nil` output from the `perform` method is not collected. 
~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  output_category nils: true
end
~~~

##### name

For both `input_category` and `output_category`, when the `name` argument is not supplied
it defaults to `:main`.

For Example:
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

##### Existing and inflight jobs

When migrating to Rocket Job 6, it is recommended to load every job and then save it back again as part of the 
deployment. When the job loads it will automatically convert itself from the old schema to the new v6 schema.

In flight jobs should not be affected, other than it is important to shutdown all running batch 
servers _before_ running any new instances.

## Rocket Job v4

Rocket Job Pro is now fully open source and included in Rocket Job under the Apache License. 

The `RocketJob::Batch` plugin now adds batch processing capabilities to break up a single task into many
concurrent workers processing slices of the entire job at the same time. 


Example:

```ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch
  
  self.description         = "Reverse names"
  self.destroy_on_complete = false
  
  # Collect the output for this job in the default output category: `:main`
  output_category

  # Method to call by all available workers at the same time.
  # Reverse the characters for each line: 
  def perform(line)
    line.reverse
  end
end
```

Upload a file for processing, for example `names.csv` which could contain:

```
jack
jane
bill
john
blake
chris
dave
marc
```

To queue the above job for processing:

```ruby
job = MyJob.new
job.upload('names.csv')
job.save!
```

Once the job has completed, download the results into a file:

```ruby
job.download('names_reversed.csv')
```

## Contributing to the documentation

To contribute to the documentation it is as easy as forking the repository
and then editing the markdown pages directly via the github web interface.

For more complex documentation changes checkout the source code locally.

#### Local checkout

* Fork the repository in github.
* Checkout your fork of the source code locally.
* Install Jekyll
~~~
    cd docs
    bundle update
~~~
* Run Jekyll web server:
~~~
    jekyll serve
~~~
* Open a web browser to view the local documentation:
    [http://127.0.0.1:4000](http://127.0.0.1:4000)
* Edit the files in the `/docs` folder.
* Refresh the page to see the changes.

Once the changes are complete, submit a github pull request.

## Upgrading to V3

V3 replaces MongoMapper with Mongoid which supports the latest MongoDB Ruby client driver.

### Upgrading Mongo Config file
Replace `mongo.yml` with `mongoid.yml`.

Start with the sample [mongoid.yml](https://github.com/rocketjob/rocketjob/blob/feature/mongoid/test/config/mongoid.yml).
 
For more information on the new [Mongoid config file](https://docs.mongodb.com/ruby-driver/master/tutorials/5.1.0/mongoid-installation/).

Note: The `rocketjob` and `rocketjob_slices` clients in the above `mongoid.yml` file are required.

### Other changes

* Arguments are no longer supported, use fields for defining all named arguments for a job.

* Replace usages of `rocket_job do` to set default values:

~~~ruby
  rocket_job do |job|
    job.priority = 25
  end
~~~

With:

~~~ruby
  self.priority = 25
~~~

* Replace `key` with `field` when adding attributes to a job:

~~~ruby
  key :inquiry_defaults, Hash
~~~

With:

~~~ruby
  field :inquiry_defaults, type: Hash, default: {}
~~~

* Replace usage of `public_rocket_job_properties` with the `user_editable` option:

~~~ruby
field :priority, type: Integer, default: 50, user_editable: true
~~~

## Ruby Support

Rocket Job is tested and supported on the following Ruby platforms:
- Ruby 2.1, 2.2, 2.3, 2.4, and above
- JRuby 9.0.5 and above

## Dependencies

* [MongoDB](https://www.mongodb.org)
    * Persists job information.
    * Version 2.7 or greater.
* [Semantic Logger](https://rocketjob.github.io/semantic_logger)
    * Highly concurrent scalable logging.

## Versioning

This project uses [Semantic Versioning](http://semver.org/).

## Author

[Reid Morrison](https://github.com/reidmorrison)

## Contributors

[Contributors](https://github.com/rocketjob/rocketjob/graphs/contributors)


# Rocket Job
[![Gem Version](https://img.shields.io/gem/v/rocketjob.svg)](https://rubygems.org/gems/rocketjob) [![Build Status](https://travis-ci.org/rocketjob/rocketjob.svg?branch=master)](https://travis-ci.org/rocketjob/rocketjob) [![Downloads](https://img.shields.io/gem/dt/rocketjob.svg)](https://rubygems.org/gems/semantic_logger) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg) [![Support](https://img.shields.io/badge/IRC%20(gitter)-Support-brightgreen.svg)](https://gitter.im/rocketjob/support)

Ruby's missing batch system

Checkout http://rocketjob.io/

![Rocket Job](http://rocketjob.io/images/rocket/rocket-icon-512x512.png)

## Documentation

* [Guide](http://rocketjob.io/)
* [API Reference](http://www.rubydoc.info/gems/rocketjob/)

## Support

* Questions? Join the chat room on Gitter for [rocketjob support](https://gitter.im/rocketjob/support)
* [Report bugs](https://github.com/rocketjob/rocketjob/issues)

## Rocket Job 4

Rocket Job Pro is now open sourced and included within Rocket Job. 

The `RocketJob::Batch` plugin now adds batch processing capabilites to break up a single task into many
concurrent workers processing slices of the entire job at the same time. 


Example:

```ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch
  
  self.description         = "Reverse names"
  self.destroy_on_complete = false
  self.collect_output      = true

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


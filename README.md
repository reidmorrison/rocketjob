# Rocket Job
[![Gem Version](https://img.shields.io/gem/v/rocketjob.svg)](https://rubygems.org/gems/rocketjob) [![Build Status](https://travis-ci.org/rocketjob/rocketjob.svg?branch=master)](https://travis-ci.org/rocketjob/rocketjob) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg) [![Support](https://img.shields.io/badge/IRC%20(gitter)-Support-brightgreen.svg)](https://gitter.im/rocketjob/support)

Ruby's missing batch system

Checkout http://rocketjob.io/

![Rocket Job](http://rocketjob.io/images/rocket/rocket-icon-512x512.png)

## Documentation

* [Guide](http://rocketjob.io/)
* [API Reference](http://www.rubydoc.info/gems/rocketjob/)

## Support

* Questions? Join the chat room on Gitter for [rocketjob support](https://gitter.im/rocketjob/support)
* [Report bugs](https://github.com/rocketjob/rocketjob/issues)

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

## Versioning

This project uses [Semantic Versioning](http://semver.org/).

## Author

[Reid Morrison](https://github.com/reidmorrison)

## Contributors

* [Chris Lamb](https://github.com/lambcr)

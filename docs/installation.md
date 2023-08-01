---
layout: default
---

# Installation

[Rocket Job][0] can run with or without Rails. Instructions for Rails and Standalone installations are listed below.

#### Table of Contents

* [Compatibility](#compatibility)
* [Install MongoDB](#install-mongodb)
* [Rails Installation](#rails-installation)
* [Standalone Installation](#standalone-installation)

## Compatibility

* Ruby 2.7, 3.2, or higher.
* JRuby 9.3, 9.4, or higher.
* [MongoDB][3] Version 4.2 or higher.
    * Note: [AWS DocumentDB][4] is _not_ compatible since it does not support capped collections.

## Install MongoDB

[Rocket Job][0] stores job data in the open source data store [MongoDB][3].

It is recommended to run MongoDB locally inside a docker container. 

To install MongoDB without using docker, see [MongoDB Downloads][5]

### Running MongoDB in a Docker container

Install Docker Desktop if not already installed, see [Docker Desktop Downloads][6].

Pull the latest Official Mongo docker image:

    docker pull mongo:6.0

Launch the Mongo Database running inside a docker container:

    docker run --name rocketjob_mongo -p 27017:27017 -d mongo:6.0 --wiredTigerCacheSizeGB 1.5

Stop the container, and keep all data:

    docker stop rocketjob_mongo

Stop the container, and _destroy_ all of its data:

    docker rm rocketjob_mongo

For more information on using the Docker Official Mongo images: [Docker Hub][7]

## Rails Installation

For an existing Rails installation, add the following lines to the bottom of the file `Gemfile`:

~~~ruby
gem "rails_semantic_logger"
gem "rocketjob"
~~~

Install gems:

~~~
bundle install
~~~

Create the file `config/mongoid.yml` as follows:

~~~yaml
# See: https://docs.mongodb.com/mongoid/master/tutorials/mongoid-configuration/
client_options: &client_options
  read:
    mode:                   :primary
  write:
    w:                      1
  connect_timeout:          10
  socket_timeout:           300
  # Includes the time taken to re-establish after a replica-set refresh
  wait_queue_timeout:       125
  server_selection_timeout: 120
  max_read_retries:         20
  max_write_retries:        10
  max_pool_size:            50
  min_pool_size:            1

mongoid_options: &mongoid_options
  preload_models: true
  scope_overwrite_exception: true
  use_utc: true

development:
  clients:
    default: &default_development
      uri: mongodb://127.0.0.1:27017/rocketjob_development
      options:
        <<: *client_options
    rocketjob:
      <<: *default_development
    rocketjob_slices:
      <<: *default_development
  options:
    <<: *mongoid_options

test:
  clients:
    default: &default_test
      uri: mongodb://127.0.0.1:27017/rocketjob_test
      options:
        <<: *client_options
    rocketjob:
      <<: *default_test
    rocketjob_slices:
      <<: *default_test
  options:
    <<: *mongoid_options

production:
  clients:
    default: &default_production
      uri: mongodb://user:secret@server.example.org:27017,server2.example.org:27017/rocketjob_production
      options:
        <<: *client_options
    rocketjob:
      <<: *default_production
    rocketjob_slices:
      <<: *default_production
      # Optionally Specify a different database or even server to store slices on
      # uri: mongodb://user:secret@server3.example.org:27017/slices_production
  options:
    <<: *mongoid_options
~~~

Alternatively, for those more familiar with mongo, the configuration file can be generated, 
and then add the above `rocketjob` and `rocketjob_slices` clients as per the configuration file above, 
using `bundle exec rails generate mongoid:config`.

The `rocketjob` and `rocketjob_slices` clients above can be changed to point to separate
database in production to spread load or to improve performance.

If you are running `Spring`, which is installed by default by Rails, stop the backgound
spring processes to get them to reload:

~~~
bin/spring stop
~~~

Start a Rocket Job worker process:

~~~
bundle exec rocketjob
~~~

Or, if you have generated bundler bin stubs:

~~~
bin/rocketjob
~~~

### Installing the Rocket Job Web Interface

[Rocket Job Web Interface][1] is a rails engine that can be mounted into any existing Rails 5 or Rails 6 application.

Add the [Rocket Job Web Interface][1] gem to your Gemfile:

~~~ruby
gem 'rocketjob_mission_control', '~> 6.0'
~~~

Install gems:

~~~
bundle install
~~~

Add the following line to `config/routes.rb` in your Rails application:

~~~ruby
mount RocketJobMissionControl::Engine => 'rocketjob'
~~~

Start the Rails server:

~~~
bin/rails s
~~~

Open a browser and navigate to the local [Rocket Job Web Interface](http://localhost:3000/rocketjob)

## Standalone Installation

When running stand-alone without Rails.

Create directories to hold the standalone Rocket Job jobs and configuration:

~~~
mkdir standalone
mkdir standalone/jobs
mkdir standalone/config
cd standalone
~~~

Create a file called `Gemfile` in the `standalone` directory with the following contents:

~~~ruby
source 'https://rubygems.org'

gem 'rocketjob', '~> 6.0'
~~~

Install the gem files:

~~~
bundle
~~~

Create a file called `mongoid.yml` in the `config` sub-directory with the following contents:

~~~yaml
# See: https://docs.mongodb.com/mongoid/master/tutorials/mongoid-configuration/
client_options: &client_options
  read:
    mode:                   :primary
  write:
    w:                      1
  connect_timeout:          10
  socket_timeout:           300
  # Includes the time taken to re-establish after a replica-set refresh
  wait_queue_timeout:       125
  server_selection_timeout: 120
  max_read_retries:         20
  max_write_retries:        10
  max_pool_size:            50
  min_pool_size:            1

mongoid_options: &mongoid_options
  preload_models: true
  scope_overwrite_exception: true
  use_utc: true

development:
  clients:
    default: &default_development
      uri: mongodb://127.0.0.1:27017/rocketjob_development
      options:
        <<: *client_options
    rocketjob:
      <<: *default_development
    rocketjob_slices:
      <<: *default_development
  options:
    <<: *mongoid_options

test:
  clients:
    default: &default_test
      uri: mongodb://127.0.0.1:27017/rocketjob_test
      options:
        <<: *client_options
    rocketjob:
      <<: *default_test
    rocketjob_slices:
      <<: *default_test
  options:
    <<: *mongoid_options

production:
  clients:
    default: &default_production
      uri: mongodb://user:secret@server.example.org:27017,server2.example.org:27017/rocketjob_production
      options:
        <<: *client_options
    rocketjob:
      <<: *default_production
    rocketjob_slices:
      <<: *default_production
      # Optionally Specify a different database or even server to store slices on
      # uri: mongodb://user:secret@server3.example.org:27017/slices_production
  options:
    <<: *mongoid_options
~~~

Create a new Job for the workers to process. Create a file called `hello_world_job.rb`
in the `jobs` directory with the following contents:

~~~ruby
class HelloWorldJob < RocketJob::Job
  def perform
    puts "HELLO WORLD"
  end
end
~~~

Start a worker process, from within the `standalone` directory:

~~~
bundle exec rocketjob
~~~

Open a new console to queue a new job request:

~~~
bundle exec irb
~~~

Enter the following code:

~~~ruby
require 'rocketjob'
require 'yaml'

# Log to development.log
SemanticLogger.add_appender(file_name: 'development.log', formatter: :color)
SemanticLogger.default_level = :debug

# Configure Mongo
RocketJob::Config.load!('development', 'config/mongo.yml')

require_relative 'jobs/hello_world_job'

HelloWorldJob.create!
~~~

The console running `rocketjob` should show something similar to:

~~~
2016-05-09 21:29:24.349058 I [64431:rocketjob 008] [job:57313973a26ec03710000001] HelloWorldJob -- Start #perform
HELLO WORLD
2016-05-09 21:29:24.349365 I [64431:rocketjob 008] [job:57313973a26ec03710000001] (0.120ms) HelloWorldJob -- Completed #perform
~~~

### Standalone Rocket Job Web Interface

In order to install [Rocket Job Web Interface][1] in a stand-alone environment, we need to
host it in a "shell" rails application as follows:

Create shell application:

~~~
gem install rails
rails new rjmc
cd rjmc
~~~

Add the following lines to the bottom of the file `Gemfile`:

~~~ruby
gem 'rails_semantic_logger'
gem 'rocketjob', '~> 6.0'
gem 'rocketjob_mission_control', '~> 6.0'
gem 'puma'
~~~

Install gems:

~~~
bundle install
~~~

Add the following line to `config/routes.rb`:

~~~ruby
mount RocketJobMissionControl::Engine => '/'
~~~

Re-load spring:

~~~
bin/spring stop
~~~

Generate Mongo Configuration file:

~~~
bundle exec rails generate mongoid:config
~~~

Edit the file config/mongoid.yml with the MongoDB server addresses.

Add the `rocketjob` and `rocketjob_slices` clients as per the example below to every environment.

~~~yaml
development:
  clients:
    default: &default_development
      uri: mongodb://127.0.0.1:27017/rocketjob_development
      options:
        <<: *client_options
        write:
          w:   0
        max_pool_size: 5
        min_pool_size: 1
    rocketjob:
      <<: *default_development
    rocketjob_slices:
      <<: *default_development
  options:
    <<: *mongoid_options
~~~

The `rocketjob` and `rocketjob_slices` clients above can be changed to point to separate
database in production to spread load or to improve performance.

Start the stand-alone [Rocket Job Web Interface][1]:

~~~
bin/rails s
~~~

Open a browser and navigate to the [local Rocket Job Web Interface](http://localhost:3000)

[0]: https://rocketjob.io
[1]: mission_control.html
[2]: https://rocketjob.github.io/semantic_logger
[3]: https://mongodb.com
[4]: https://docs.aws.amazon.com/documentdb/latest/developerguide/mongo-apis.html#mongo-apis-dababase-administrative
[5]: https://www.mongodb.com/try/download/community
[6]: https://www.docker.com/products/docker-desktop
[7]: https://hub.docker.com/_/mongo?

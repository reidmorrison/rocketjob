---
layout: default
---

## Installation

[Rocket Job][0] can run with or without Rails. Instructions for Rails and Standalone installations are listed below.

### Compatibility

* Ruby 2.1, 2.2, 2.3, 2.4.1 or greater
* JRuby 1.7, 9.0.4.0, or greater
* [MongoDB][3] V2.6 or greater is required.

### MongoDB

[Rocket Job][0] stores jobs in the open source data store [MongoDB][3].
Installing [MongoDB][3] is relatively straight forward.

For example, installing [MongoDB][3] on a Mac running homebrew:

~~~
brew install mongodb
~~~

Then follow the on-screen instructions to start [MongoDB][3].

For other platforms, see [MongoDB Downloads](https://www.mongodb.org/downloads)

## Rails Installation

For an existing Rails installation, add the following lines to the bottom of the file `Gemfile`:

~~~ruby
gem 'rails_semantic_logger'
gem 'rocketjob', '~> 3.0'
~~~

Install gems:

~~~
bundle install
~~~

Generate Mongo Configuration file if one does not already exist:

~~~
bundle exec rails generate mongoid:config
~~~

Edit the file config/mongoid.yml with the MongoDB server addresses.

Add the `rocketjob` and `rocketjob_slices` clients as per the example below to every environment.

~~~yaml
development:
  clients:
    default: &default_development
      uri: mongodb://localhost:27017/rocketjob_development
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

### Installing RocketJob Mission Control (Web Interface)

[Rocket Job Mission Control][1] is the web interface for [Rocket Job][0].
It is a rails engine that can be added to any existing Rails 4 or Rails 5 rails application.

Add the [Rocket Job Mission Control][1] gem to your Gemfile

~~~ruby
gem 'rocketjob_mission_control', '~> 3.0'
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

Open a browser and navigate to the local [Rocket Job Mission Control](http://localhost:3000/rocketjob)

## Standalone Installation

When running stand-alone without Rails.

Create directories to hold the standalone RocketJob jobs and configuration:

~~~
mkdir standalone
mkdir standalone/jobs
mkdir standalone/config
cd standalone
~~~

Create a file called `Gemfile` in the `standalone` directory with the following contents:

~~~ruby
source 'https://rubygems.org'

gem 'rocketjob', '~> 3.0'
~~~

Install the gem files:

~~~
bundle
~~~

Create a file called `mongoid.yml` in the `config` sub-directory with the following contents:

~~~yaml
# See: https://docs.mongodb.com/ruby-driver/master/tutorials/5.1.0/mongoid-installation/
client_options: &client_options
  read:
    mode:             :primary
  write:
    w:                0
  max_pool_size:      50
  min_pool_size:      10
  connect_timeout:    5
  socket_timeout:     300
  wait_queue_timeout: 5

mongoid_options: &mongoid_options
  # Includes the root model name in json serialization. (default: false)
  # include_root_in_json: false

  # Include the _type field in serialization. (default: false)
  # include_type_for_serialization: false

  # Preload all models in development, needed when models use
  # inheritance. (default: false)
  preload_models: true

  # Raise an error when performing a #find and the document is not found.
  # (default: true)
  # raise_not_found_error: true

  # Raise an error when defining a scope with the same name as an
  # existing method. (default: false)
  scope_overwrite_exception: true

  # Use Active Support's time zone in conversions. (default: true)
  # use_activesupport_time_zone: true

  # Ensure all times are UTC in the app side. (default: false)
  use_utc: true

development:
  clients:
    default: &default_development
      uri: mongodb://localhost:27017/rocketjob_development
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

test:
  clients:
    default: &default_test
      uri: mongodb://localhost:27017/rocketjob_test
      options:
        <<: *client_options
        write:
          w:           1
        max_pool_size: 5
        min_pool_size: 1
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
        write:
          w:   0
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

[Rocket Job Mission Control][1] is the web interface for [Rocket Job][0].
In order to install [Rocket Job Mission Control][1] in a stand-alone environment, we need to
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
gem 'rocketjob', '~> 3.0'
gem 'rocketjob_mission_control', '~> 3.0'
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
bundle exec rails generate mongo_mapper:config
~~~

Edit the file config/mongoid.yml with the MongoDB server addresses.

Add the `rocketjob` and `rocketjob_slices` clients as per the example below to every environment.

~~~yaml
development:
  clients:
    default: &default_development
      uri: mongodb://localhost:27017/rocketjob_development
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

Start the stand-alone [Rocket Job Mission Control][1]:

~~~
bin/rails s
~~~

Open a browser and navigate to the local [Rocket Job Mission Control](http://localhost:3000)

### [Next: Guide ==>](guide.html)

[0]: http://rocketjob.io
[1]: mission_control.html
[2]: http://rocketjob.github.io/semantic_logger
[3]: http://mongodb.org

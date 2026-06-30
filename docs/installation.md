---
layout: default
---

## Installation
{:.no_toc}

Rocket Job runs with or without Rails. This guide covers both, plus the optional web interface,
[Rocket Job Mission Control](mission_control.html).

**Contents**

* TOC
{:toc}

## Compatibility

Rocket Job is tested against a matrix of Ruby, Mongoid, and Rails versions. The combinations
exercised in CI are the authoritative list; see
[ci.yml](https://github.com/reidmorrison/rocketjob/blob/master/.github/workflows/ci.yml) and
[Appraisals](https://github.com/reidmorrison/rocketjob/blob/master/Appraisals).

* **Ruby:** MRI 3.2, 3.4, and 4.0. JRuby 9.4 or newer is also supported.
* **Mongoid:** 8.1, 9.0, and 9.1.
* **Rails / Active Record:** 7.2, 8.0, and 8.1 (optional; Rocket Job also runs standalone).
* **MongoDB server:** whatever your Mongoid version supports. Mongoid 8.1 through 9.1 currently
  support MongoDB server 3.6 through 8.x. See the
  [Mongoid compatibility matrix](https://www.mongodb.com/docs/mongoid/current/compatibility/).

### AWS DocumentDB
{:.no_toc}

Rocket Job's cross-process event mechanism (used for shutdown, pause, and log-level changes)
defaults to a *tailable capped collection*, which [Amazon DocumentDB](https://aws.amazon.com/documentdb/)
does not support. To run on DocumentDB, switch the event listener to the polling strategy, which uses
a regular collection instead. Add this to an initializer (for example
`config/initializers/rocketjob.rb`):

~~~ruby
RocketJob::Event.listener_strategy = :polling
~~~

With polling enabled, control events are delivered within `RocketJob::Event.poll_interval` seconds
(default `1`). Events are stored in a regular collection bounded by a TTL index;
`RocketJob::Event.event_retention_seconds` (default one hour) controls how long an event is kept,
which is also the longest a server can be offline and still recover events on restart. On a real
MongoDB server the default capped-collection strategy remains the lowest-latency choice and needs no
configuration.

#### Event listener settings
{:.no_toc}

All of the event listener settings, with their defaults:

| Setting | Default | Applies to | Description |
|---------|---------|-----------|-------------|
| `RocketJob::Event.listener_strategy` | `:capped` | both | `:capped` tails a capped collection (lowest latency, requires capped-collection support); `:polling` polls a regular collection (works on any MongoDB-compatible store, including DocumentDB). |
| `RocketJob::Event.long_poll_seconds` | `300` | `:capped` | How long the tailable cursor waits for new events before re-issuing. |
| `RocketJob::Event.capped_collection_size` | `134217728` (128 MB) | `:capped` | Size of the capped collection, used only when it is first created. |
| `RocketJob::Event.poll_interval` | `1` | `:polling` | Seconds between polls. Bounds control-event delivery latency. |
| `RocketJob::Event.event_retention_seconds` | `3600` (1 hour) | `:polling` | TTL on stored events. Also the longest a server can be offline and still recover events on restart. |

## Licensing

A frequent objection to adopting Rocket Job is MongoDB's
[Server Side Public License](https://www.mongodb.com/legal/licensing/server-side-public-license)
(SSPL), which is not OSI-approved. It is worth being precise about what it does and does not require,
because the concern is usually broader than the license actually is.

* **Rocket Job and its client stack are permissively licensed.** Rocket Job is Apache 2.0. The gems
  it uses to talk to the database, the [`mongo`](https://github.com/mongodb/mongo-ruby-driver) driver
  and [`mongoid`](https://github.com/mongodb/mongoid), are Apache 2.0 as well. Nothing in the
  Rocket Job stack is SSPL.
* **The SSPL covers the MongoDB server, and its copyleft only triggers on offering MongoDB itself as
  a service to third parties.** Running MongoDB internally as the datastore behind your own
  application and job queue does not create an SSPL obligation. The clause is aimed at companies that
  resell a managed MongoDB-as-a-service, not at companies that simply run MongoDB.
* **A commercial license is available.** Organizations with a commercial agreement with MongoDB Inc.
  can use MongoDB under that license instead, which removes the SSPL question entirely.

This licensing shift is also not unique to MongoDB. [Redis](https://redis.io/) (2024) and
[Elasticsearch](https://www.elastic.co/) (2021) both moved to SSPL, and both have since re-added an
OSI-approved option. MongoDB remains a deliberate design choice for Rocket Job: its atomic
`find_and_modify` is what lets thousands of workers claim jobs and slices without colliding, and it
spills from memory to disk, which is what makes processing very large files practical. See
[Architecture](architecture.html) for why the datastore is MongoDB specifically.

## Install MongoDB

Rocket Job stores all job data in [MongoDB](https://www.mongodb.com). The simplest way to run it
locally is in a Docker container. To install MongoDB without Docker, see the
[MongoDB Community downloads](https://www.mongodb.com/try/download/community).

### Run MongoDB in Docker

Install [Docker Desktop](https://www.docker.com/products/docker-desktop) if you do not already have
it, then start MongoDB:

~~~bash
docker run --name rocketjob_mongo -p 27017:27017 -d mongo:8.0
~~~

Useful follow-up commands:

~~~bash
# Stop the container, keeping its data
docker stop rocketjob_mongo

# Start it again later
docker start rocketjob_mongo

# Remove the container and destroy all of its data
docker rm rocketjob_mongo
~~~

For more on the official image, see [mongo on Docker Hub](https://hub.docker.com/_/mongo). In
production, sizing the WiredTiger cache is worthwhile, for example
`--wiredTigerCacheSizeGB 1.5`.

## Configure MongoDB

Rocket Job needs two MongoDB clients, defined in `config/mongoid.yml`:

* `rocketjob`: stores the jobs themselves.
* `rocketjob_slices`: stores the input and output slices for batch jobs.

Both can point at the same database in development. In production they can be split onto separate
databases, or even separate servers, to spread load. Use this file for both Rails and standalone
installations:

~~~yaml
# See: https://www.mongodb.com/docs/mongoid/current/reference/configuration/
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
  use_utc:        true

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
      # Optionally point slices at a different database or even a different server:
      # uri: mongodb://user:secret@server3.example.org:27017/slices_production
  options:
    <<: *mongoid_options
~~~

If you already have a Mongoid configuration (for example from `bundle exec rails generate
mongoid:config`), just add the `rocketjob` and `rocketjob_slices` clients shown above to every
environment.

## Rails Installation

Add Rocket Job to an existing Rails 7.2 or newer application.

### 1. Add the gems

Add to the bottom of your `Gemfile`:

~~~ruby
gem "rails_semantic_logger"
gem "rocketjob"
~~~

~~~bash
bundle install
~~~

### 2. Configure MongoDB

Create `config/mongoid.yml` as shown in [Configure MongoDB](#configure-mongodb) above.

If you are running `Spring` (installed by default in Rails), restart it so the new configuration is
picked up:

~~~bash
bin/spring stop
~~~

### 3. Start a worker

~~~bash
bundle exec rocketjob
~~~

Or, if you have generated bundler binstubs:

~~~bash
bin/rocketjob
~~~

That is a complete Rails installation. Define jobs under `app/jobs` and queue them with
`MyJob.create!`. See the [Programmer's Guide](guide.html).

### Install the web interface

[Rocket Job Mission Control](mission_control.html) is a Rails engine that mounts into your
application.

Add the gem:

~~~ruby
gem "rocketjob_mission_control", "~> 6.0"
~~~

~~~bash
bundle install
~~~

Mount the engine in `config/routes.rb`:

~~~ruby
mount RocketJobMissionControl::Engine => "rocketjob"
~~~

Start the Rails server and open
[http://localhost:3000/rocketjob](http://localhost:3000/rocketjob):

~~~bash
bin/rails s
~~~

## Standalone Installation

Run Rocket Job without Rails.

### 1. Create the project

~~~bash
mkdir -p standalone/jobs standalone/config
cd standalone
~~~

### 2. Add the gem

Create `Gemfile`:

~~~ruby
source "https://rubygems.org"

gem "rocketjob"
~~~

~~~bash
bundle install
~~~

### 3. Configure MongoDB

Create `config/mongoid.yml` as shown in [Configure MongoDB](#configure-mongodb) above.

### 4. Write a job

Create `jobs/hello_world_job.rb`:

~~~ruby
class HelloWorldJob < RocketJob::Job
  def perform
    puts "Hello World"
  end
end
~~~

### 5. Start a worker

From inside the `standalone` directory:

~~~bash
bundle exec rocketjob
~~~

### 6. Queue a job

Open another console (`bundle exec irb`) and queue the job:

~~~ruby
require "rocketjob"

# Log to development.log using the colorized formatter
SemanticLogger.add_appender(file_name: "development.log", formatter: :color)
SemanticLogger.default_level = :debug

# Load config/mongoid.yml for the development environment
RocketJob::Config.load!("development")

require_relative "jobs/hello_world_job"

HelloWorldJob.create!
~~~

The worker process picks up the job and logs something like:

~~~
I [job:5731...] HelloWorldJob -- Start #perform
Hello World
I [job:5731...] (0.120ms) HelloWorldJob -- Completed #perform
~~~

`RocketJob::Config.load!` reads `config/mongoid.yml` relative to the current directory by default.
Pass an explicit path as the second argument to load it from elsewhere, and a third argument to
load a [Symmetric Encryption](https://github.com/reidmorrison/symmetric-encryption) configuration file.

### Standalone web interface

[Rocket Job Mission Control](mission_control.html) is a Rails engine, so running it standalone means
hosting it in a minimal "shell" Rails application.

Create the shell application:

~~~bash
gem install rails
rails new rjmc
cd rjmc
~~~

Add to the bottom of the `Gemfile`:

~~~ruby
gem "rails_semantic_logger"
gem "rocketjob"
gem "rocketjob_mission_control", "~> 6.0"
gem "puma"
~~~

~~~bash
bundle install
~~~

Mount the engine at the root in `config/routes.rb`:

~~~ruby
mount RocketJobMissionControl::Engine => "/"
~~~

Restart Spring:

~~~bash
bin/spring stop
~~~

Generate a Mongoid configuration file and edit it to add the `rocketjob` and `rocketjob_slices`
clients to every environment, as in [Configure MongoDB](#configure-mongodb):

~~~bash
bundle exec rails generate mongoid:config
~~~

Start the server and open [http://localhost:3000](http://localhost:3000):

~~~bash
bin/rails s
~~~

## Next steps

* [Programmer's Guide](guide.html): the full job API, fields, scheduling, throttling, and callbacks.
* [Batch Guide](batch.html): large files, tabular data, and parallel processing.
* [Mission Control](mission_control.html): the web interface.
* [Dirmon](dirmon.html): trigger jobs from arriving files.

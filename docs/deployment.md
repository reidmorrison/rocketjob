---
layout: default
---

## Docker

The easiest way to run the Rocket Server process in most cloud environments is to run it in a fully self contained
Docker container.

The cloud environment should be configured to start the appropriate number of instances, and then restart
them automatically when they stop. This way new images can be deployed simply by restarting the cluster.

The size of the cluster can be grown dynamically based on load so that large clusters are not sitting idle.

### Build a Docker Image

To build a docker image, we create a file in the root of the application called `Dockerfile`.

~~~Dockerfile
FROM ruby:2.7
WORKDIR /opt/rocketjob

# Installs MySQL and Postgres Client Dependencies
RUN set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends default-mysql-client-core postgresql-client

# Copy Ruby code into Docker instance.
COPY . .

# Install Gems.
RUN echo "===== Installing Gems =====" \
    && bundle config set without 'development test' \
    && bundle install --jobs 4 --retry 5 --quiet

CMD ["bin/rocketjob", "--quiet"]
~~~

Build the container

    docker build -t rocketjob_server .

Start Rocket Job Batch Workers, and remove container on completion

    docker run -d --rm rocketjob_server

Start a bash shell:

    docker run -it --rm rocketjob_server bash

Start a rails console:

    docker run -it --rm rocketjob_server bin/rails c

Attach to an already running container

    docker ps
    # Enter the container id returned above:
    docker exec -it `container_id` /bin/bash

Kill a running container

    docker ps
    # Enter the container id returned above:
    docker kill `container_id`

To cleanup local partial and untagged builds.

    docker system prune -f

#### Configuration

To run the above image locally the hostname for the mongo server should be set to `host.docker.internal:27017`
so that it can use the MongoDB instance already running, per the steps in the [Installation Guide](/installation#install-mongodb)

In an AWS production environment we recommend storing all configuration in a centralized configuration store using
[Secret Config][1]. Then the relevant settings can be overridden using environment variables when running locally.
Refer to the docker help `run` option `--env-file`.

## Capistrano Recipe

Below is an example Capistrano recipe that can be used to start or stop Rocket Job servers:

~~~ruby
# ====================================
# Rocket Job Server Tasks
# ====================================
namespace :rocketjob do
  desc 'Start a rocket_job server. optional arg: HOSTFILTER=server1,server2 --count 2 --filter "DirmonJob|WeeklyReportJob"'
  task :start do |t, args|
    count   = (ENV['count'] || 1).to_i
    filter  = "--filter #{ENV['filter']}" if ENV['filter']
    workers = "--workers #{ENV['workers']}" if ENV['workers']
    count.times do
      run "cd #{component_path} && nohup bin/rocketjob --quiet #{filter} #{workers} >> #{component_path}/log/rocketjob.log 2>&1 & sleep 2"
    end
  end

  desc 'Stop all rocket_job servers on a host. optional arg: HOSTFILTER=server1,server2'
  task :stop do |t, args|
    run 'pkill -u rails -f bin/rocketjob'
  end
end
~~~

## Large Multi-Server Deployment

The instructions below are tailored to a large deployment of Rocket Job. For a small
production installation the regular installation instructions are sufficient to
run the Rocket Job and MongoDB processes on a single server.

### MongoDB

In a high availability environment it is recommended to setup a MongoDB Replica set consisting
of 2 full servers and 1 arbiter node, or 3 full servers if desired. One of the servers can run
in a second data center to facilitate fail over to the second data center if needed.

This setup will ensure that if the master server goes down for any reason that the second
server will take over. This transition should occur automatically and without any errors or
failed jobs. Rocket Job will detect the change in master and automatically connect to the
new master and continue processing.

Update the file config/mongoid.yml with the hostname for the production MongoDB Server / Replica set.

### Servers

Each machine can run multiple Rocket Job servers, with 10 threads each. For example:

~~~
nohup bundle exec rocketjob --quiet >> log/rocketjob.log 2>&1
~~~

The Web UI can be mounted as an engine into the existing Rails application which
can be run on multiple servers for high availability.

The number of processes on each server should be determined based on load testing.
The objective is to find the right number of processes and threads to maximize utilization
without overwhelming the CPU, disk, or memory utilization.

### Monitoring

To monitor the MongoDB server while the workers are processing jobs:

~~~
mongostat --host localhost:27017 --discover
~~~

Replace `localhost:27017` as needed.

### Directory Monitor

Before files can be detected and processed via the Dirmon Entries created in the Web UI,
it is necessary to create the directory monitor Job.

Run the following from an application console:

~~~ruby
RocketJob::Jobs::DirmonJob.create!
~~~

[1] https://config.rocketjob.io

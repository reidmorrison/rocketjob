---
layout: default
---

## Deployment
{:.no_toc}

A Rocket Job "server" is the `bin/rocketjob` process. It registers itself in MongoDB, starts a
pool of worker threads (10 by default), and pulls queued jobs to run. Deploying Rocket Job means
running one or more of these processes and pointing them at your MongoDB.

You scale by running more servers. There is no central coordinator to install: every server claims
work directly from MongoDB using atomic operations, so you can start and stop servers freely. To
deploy new code, build a new image (or pull new code) and restart the servers.

This guide covers the two common ways to run servers, how to make MongoDB highly available, and the
one-time steps to perform after the first deployment. It assumes you have already configured
`config/mongoid.yml` as described in the [Installation Guide](installation.html#configure-mongodb).

**Contents**

* TOC
{:toc}

## Deploy with Docker

Running each server in a self-contained Docker container is the simplest option in most cloud
environments. Configure your platform (ECS, Kubernetes, Nomad, and so on) to run the desired number
of containers and to restart them automatically when they exit. New code is then rolled out by
restarting the containers, and the cluster can be grown or shrunk based on load.

### Step 1: Create a Dockerfile

Add a file named `Dockerfile` to the root of your application:

~~~dockerfile
FROM ruby:3.4

WORKDIR /opt/rocketjob

# Optional: database client libraries. Only needed when jobs read directly
# from MySQL or PostgreSQL (for example a Batch job using upload_arel).
# Remove this block if your jobs do not touch a relational database.
RUN set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends default-mysql-client postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy the application code into the image.
COPY . .

# Install gems, skipping the development and test groups.
RUN bundle config set --local without 'development test' \
    && bundle install --jobs 4 --retry 5 --quiet

# Start a Rocket Job server. Logs go to stdout so the container platform can collect them.
CMD ["bin/rocketjob"]
~~~

Use a Ruby version that Rocket Job supports (3.2, 3.4, or 4.0). See
[Compatibility](installation.html#compatibility).

Add `--quiet` to the `CMD` if you would rather log only to a file instead of stdout, for example
`CMD ["bin/rocketjob", "--quiet"]`.

### Step 2: Build the image

~~~bash
docker build -t rocketjob_server .
~~~

### Step 3: Tell the server where MongoDB is

The server reads `config/mongoid.yml`. The challenge in production is supplying credentials and host
names without baking them into the image.

**Local testing.** To run the image against a MongoDB already running on your host (per the
[Installation Guide](installation.html#install-mongodb)), set the MongoDB hostname to
`host.docker.internal:27017` so the container can reach out to the host.

**Production.** Store all configuration in a central store using
[Secret Config](https://config.rocketjob.io), and override individual settings with environment
variables where needed. Pass environment variables into the container with Docker's
`--env-file` option (see `docker run --help`), or through your orchestrator's secret mechanism.

### Step 4: Run the server

Start a server in the background and remove the container when it exits:

~~~bash
docker run -d --rm rocketjob_server
~~~

Run that command once per server you want in the cluster, or let your orchestrator manage the
replica count.

### Useful Docker commands

~~~bash
# Open a bash shell in a fresh container
docker run -it --rm rocketjob_server bash

# Open a Rails console in a fresh container
docker run -it --rm rocketjob_server bin/rails c

# List running containers, then attach a shell to one of them
docker ps
docker exec -it <container_id> /bin/bash

# Stop a running container
docker kill <container_id>

# Clean up dangling and untagged local images
docker system prune -f
~~~

## Deploy with Capistrano

For traditional (non-containerized) servers, the recipe below starts and stops Rocket Job processes
over SSH. Each `bin/rocketjob` process runs detached with `nohup`, writing to a log file.

~~~ruby
# ====================================
# Rocket Job Server Tasks
# ====================================
namespace :rocketjob do
  desc 'Start rocket_job servers. Optional: HOSTFILTER=server1,server2 count=2 workers=10 include="DirmonJob|WeeklyReportJob"'
  task :start do
    count          = (ENV["count"] || 1).to_i
    include_filter = "--include #{ENV['include']}" if ENV["include"]
    workers        = "--workers #{ENV['workers']}" if ENV["workers"]
    count.times do
      run "cd #{component_path} && nohup bin/rocketjob --quiet #{include_filter} #{workers} >> #{component_path}/log/rocketjob.log 2>&1 & sleep 2"
    end
  end

  desc "Stop all rocket_job servers on a host. Optional: HOSTFILTER=server1,server2"
  task :stop do
    run "pkill -u rails -f bin/rocketjob"
  end
end
~~~

`pkill` sends `SIGTERM`, which Rocket Job handles as a graceful shutdown: each server finishes the
jobs already in progress before exiting. To stop servers without shelling into each host, use the
event-based command instead, which signals servers through MongoDB:

~~~bash
bin/rocketjob --stop
~~~

### Limiting a server to specific jobs

The `--include` flag above restricts a server to job classes matching a regular expression, so you
can dedicate a pool of servers to a heavy or latency-sensitive job class while another pool handles
everything else. The companion `--exclude` and `--where` flags are documented in the
[Programmer's Guide](guide.html#limiting-which-jobs-a-server-runs).

## High-availability MongoDB

For a small production install, a single MongoDB server alongside the Rocket Job processes is
sufficient. For high availability, run a [MongoDB replica set](https://www.mongodb.com/docs/manual/replication/).

A common setup is two full data-bearing members plus one arbiter, or three full members. Placing one
member in a second data center allows failover across data centers.

If the primary goes down, the replica set elects a new primary automatically. Rocket Job detects the
change, reconnects to the new primary, and continues processing without failed jobs.

Point `config/mongoid.yml` at the replica set by listing all members in the connection URI, for
example:

~~~yaml
uri: mongodb://user:secret@server1.example.org:27017,server2.example.org:27017/rocketjob_production?replicaSet=rs0
~~~

## Running multiple servers per host

A single host can run several Rocket Job servers, each with its own pool of worker threads (10 by
default). Adjust the thread count per server with `--workers`:

~~~bash
nohup bundle exec rocketjob --quiet --workers 10 >> log/rocketjob.log 2>&1 &
~~~

The right number of servers and threads per host is found through load testing. The goal is to
maximize throughput without saturating the host's CPU, memory, or disk, or overwhelming MongoDB.

The web interface, [Mission Control](mission_control.html), is a Rails engine. Mount it into your
Rails application and run it on multiple hosts behind a load balancer for high availability.

## After deployment

### Start the directory monitor

If you use [Dirmon](dirmon.html) to pick up files as they arrive, the directory monitor must be
created once per environment from an application console (`RocketJob::Jobs::DirmonJob.create!`). It
then reschedules itself, so this is a one-time step. See
[Starting the directory monitor](dirmon.html#starting-the-directory-monitor) for the details.

### Monitor MongoDB

Because all coordination happens in MongoDB, watching the database is the best way to observe the
cluster under load. `mongostat` reports per-second operation counts across every member:

~~~bash
mongostat --host localhost:27017 --discover
~~~

Replace `localhost:27017` with one of your MongoDB hosts. The `--discover` flag follows the rest of
the replica set automatically.

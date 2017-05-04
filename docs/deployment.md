---
layout: default
---

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

### [Next: Rocket Job Pro ==>](pro.html)

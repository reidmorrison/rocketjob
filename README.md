# rocketjob[![Build Status](https://secure.travis-ci.org/rocketjob/rocketjob.png?branch=master)](http://travis-ci.org/rocketjob/rocketjob) ![](http://ruby-gem-downloads-badge.herokuapp.com/rocketjob?type=total)

High volume, priority based, background job processing solution for Ruby.

## Status

Beta - Feedback on the API is welcome. API may change.

Already in use in production internally processing large files with millions
of records, as well as large jobs to walk though large databases.

## Why?

We have tried for years to make both `resque` and more recently `sidekiq`
work for large high performance batch processing.
Even `sidekiq-pro` was purchased and used in an attempt to process large batches.

Unfortunately, after all the pain and suffering with the existing asynchronous
worker solutions none of them have worked in our production environment without
significant hand-holding and constant support. Mysteriously the odd record/job
was disappearing when processing 100's of millions of jobs with no indication
where those lost jobs went.

In our environment we cannot lose even a single job or record, as all data is
business critical. The existing batch processing solution do not supply any way
to collect the output from batch processing and as a result every job has custom
code to collect it's output. rocketjob has built in support to collect the results
of any batch job.

High availability and high throughput were being limited by how much we could get
through `redis`. Being a single-threaded process it is constrained to a single
CPU. Putting `redis` on a large multi-core box does not help since it will not
use more than one CPU at a time.
Additionally, `redis` is constrained to the amount of physical memory is available
on the server.
`redis` worked very well when processing was below around 100,000 jobs a day,
when our workload suddenly increased to over 100,000,000 a day it could not keep
up. Its single CPU would often hit 100% CPU utilization when running many `sidekiq-pro`
servers. We also had to store actual job data in a separate MySQL database since
it would not fit in memory on the `redis` server.

`rocketjob` was created out of necessity due to constant support. End-users were
constantly contacting the development team to ask on the status of "hung" or
"in-complete" jobs, as part of our DevOps role.

Another significant production support challenge is trying to get `resque` or `sidekiq`
to process the batch jobs in a very specific order. Switching from queue-based
to priority-based job processing means that all jobs are processed in the order of
their priority and not what queues are defined on what servers and in what quantity.
This approach has allowed us to significantly increase the CPU and IO utilization
across all worker machines. The traditional queue based approach required constant
tweaking in the production environment to try and balance workload without overwhelming
any one server.

End-users are now able to modify the priority of their various jobs at runtime
so that they can get that business critical job out first, instead of having to
wait for other jobs of the same type/priority to finish first.

Since `rocketjob` uploads the entire file, or all data for processing it does not
require jobs to store the data in other databases.
Additionally, `rocketjob` supports encryption and compression of any data uploaded
into Sliced Jobs to ensure PCI compliance and to prevent sensitive from being exposed
either at rest in the data store, or in flight as it is being read or written to the
backend data store.
Often large files received for processing contain sensitive data that must not be exposed
in the backend job store. Having this capability built-in ensures all our jobs
are properly securing sensitive data.

Since moving to `rocketjob` our production support has diminished and now we can
focus on writing code again. :)

## Introduction

`rocketjob` is a global "priority based queue" (https://en.wikipedia.org/wiki/Priority_queue)
All jobs are placed in a single global queue and the job with the highest priority
is processed first. Jobs with the same priority are processed on a first-in
first-out (FIFO) basis.

This differs from the traditional approach of separate queues for jobs which
quickly becomes cumbersome when there are for example over a hundred different
types of jobs.

The global priority based queue ensures that the servers are utilized to their
capacity without requiring constant manual intervention.

`rocketjob` is designed to handle hundreds of millions of concurrent jobs
that are often encountered in high volume batch processing environments.
It is designed from the ground up to support large batch file processing.
For example a single file that contains millions of records to be processed
as quickly as possible without impacting other jobs with a higher priority.

## Management

The companion project [rocketjob mission control](https://github.com/rocketjob/rocket_job_mission_control)
contains the Rails Engine that can be loaded into your Rails project to add
a web interface for viewing and managing `rocketjob` jobs.

`rocketjob mission control` can also be run stand-alone in a shell Rails application.

By separating `rocketjob mission control` into a separate gem means it does not
have to be loaded where `rocketjob` jobs are defined or run.

## Jobs

Simple single task jobs:

Example job to run in a separate worker process

```ruby
class MyJob < RocketJob::Job
  # Method to call asynchronously by the worker
  def perform(email_address, message)
    # For example send an email to the supplied address with the supplied message
    send_email(email_address, message)
  end
end
```

To queue the above job for processing:

```ruby
MyJob.perform_later('jack@blah.com', 'lets meet')
```

## Directory Monitoring

A common task with many batch processing systems is to look for the appearance of
new files and kick off jobs to process them. `DirmonJob` is a job designed to do
this task.

`DirmonJob` runs every 5 minutes by default, looking for new files that have appeared
based on configured entries called `DirmonEntry`. Ultimately these entries will be
configurable via `rocketjob_mission_control`, the web management interface for `rocketjob`.

Example, creating a `DirmonEntry`

```ruby
RocketJob::DirmonEntry.new(
  path:         'path_to_monitor/*',
  job:          'Jobs::TestJob',
  arguments:    [ { input: 'yes' } ],
  properties:   { priority: 23, perform_method: :event },
  archive_directory: '/exports/archive'
)
```

The attributes of DirmonEntry:

* path <String>

Wildcard path to search for files in.
For details on valid path values, see: http://ruby-doc.org/core-2.2.2/Dir.html#method-c-glob

Example:

    * input_files/process1/*.csv*
    * input_files/process2/**/*

* job <String>

Name of the job to start

* arguments <Array>

Any user supplied arguments for the method invocation
All keys must be UTF-8 strings. The values can be any valid BSON type:

    * Integer
    * Float
    * Time    (UTC)
    * String  (UTF-8)
    * Array
    * Hash
    * True
    * False
    * Symbol
    * nil
    * Regular Expression

_Note_: Date is not supported, convert it to a UTC time

* properties <Hash>

Any job properties to set.

Example, override the default job priority:

```ruby
{ priority: 45 }
```

* archive_directory

Archive directory to move the file to before the job is started. It is important to
move the file before it is processed so that it is not picked up again for processing.
If no archive_directory is supplied the file will be moved to a folder called '_archive'
in the same folder as the file itself.

If the `path` above is a relative path the relative path structure will be
maintained when the file is moved to the archive path.

* enabled <Boolean>

Allow a monitoring entry to be disabled so that it is ignored by `DirmonJob`.
This feature is useful for operations to temporarily stop processing files
from a particular source, without having to completely delete the `DirmonEntry`.
It can also be used to create a `DirmonEntry` without it becoming immediately
active.
```

### Starting the directory monitor

The directory monitor job only needs to be started once per installation by running
the following code:

```ruby
RocketJob::Jobs::DirmonJob.perform_later
```

The polling interval to check for new files can be modified when starting the job
for the first time by adding:
```ruby
RocketJob::Jobs::DirmonJob.perform_later do |job|
  job.check_seconds = 180
end
```

The default priority for `DirmonJob` is 40, to increase it's priority:
```ruby
RocketJob::Jobs::DirmonJob.perform_later do |job|
  job.check_seconds = 300
  job.priority      = 25
end
```

Once `DirmonJob` has been started it's priority and check interval can be
changed at any time as follows:

```ruby
RocketJob::Jobs::DirmonJob.first.set(check_seconds: 180, priority: 20)
```

The `DirmonJob` will automatically re-schedule a new instance of itself to run in
the future after it completes a each scan/run. If successful the current job instance
will destroy itself.

In this way it avoids having a single Directory Monitor process that constantly
sits there monitoring folders for changes. More importantly it avoids a "single
point of failure" that is typical for earlier directory monitoring solutions.
Every time `DirmonJob` runs and scans the paths for new files it could be running
on a new worker. If any server/worker is removed or shutdown it will not stop
`DirmonJob` since it will just run on another worker instance.

There can only be one `DirmonJob` instance `queued` or `running` at a time. Any
attempt to start a second instance will result in an exception.

If an exception occurs while running `DirmonJob`, a failed job instance will remain
in the job list for problem determination. The failed job cannot be restarted and
should be destroyed if no longer needed.

## Rails Configuration

MongoMapper will already configure itself in Rails environments. `rocketjob` can
be configured to use a separate MongoDB instance from the Rails application as follows:

For example, we may want `RocketJob::Job` to be stored in a Mongo Database that
is replicated across data centers, whereas we may not want to replicate the
`RocketJob::SlicedJob`** slices due to it's sheer volume.

```ruby
config.before_initialize do
  # Share the common mongo configuration file
  config_file = root.join('config', 'mongo.yml')
  if config_file.file?
    config = YAML.load(ERB.new(config_file.read).result)
    if config["#{Rails.env}_rocketjob]
      options = (config['options']||{}).symbolize_keys
      options[:logger] = SemanticLogger::DebugAsTraceLogger.new('Mongo:rocketjob')
      RocketJob::Config.mongo_connection = Mongo::MongoClient.from_uri(config['uri'], options)
    end
    # It is also possible to store the jobs themselves in a separate MongoDB database
    if config["#{Rails.env}_rocketjob_work]
      options = (config['options']||{}).symbolize_keys
      options[:logger] = SemanticLogger::DebugAsTraceLogger.new('Mongo:rocketjob_work')
      RocketJob::Config.mongo_work_connection = Mongo::MongoClient.from_uri(config['uri'], options)
    end
  else
    puts "\nmongo.yml config file not found: #{config_file}"
  end
end
```

For an example config file, `config/mongo.yml`, see [mongo.yml](https://github.com/rocketjob/rocketjob/blob/master/test/config/mongo.yml)

## Standalone Configuration

When running `rocketjob` in a standalone environment without Rails, the MongoDB
connections will need to be setup as follows:

```ruby
options = {
  pool_size:    50,
  pool_timeout: 5,
  logger:       SemanticLogger::DebugAsTraceLogger.new('Mongo:Work'),
}

# For example when using a replica-set for high availability
uri = 'mongodb://mongo1.site.com:27017,mongo2.site.com:27017/production_rocketjob'
RocketJob::Config.mongo_connection = Mongo::MongoClient.from_uri(uri, options)

# Use a separate database, or even server for `RocketJob::SlicedJob` slices
uri = 'mongodb://mongo1.site.com:27017,mongo2.site.com:27017/production_rocketjob_slices'
RocketJob::Config.mongo_work_connection = Mongo::MongoClient.from_uri(uri, options)
```

## Requirements

MongoDB V2.6 or greater. V3 is recommended

* V2.6 includes a feature to allow lookups using the `$or` clause to use an index

## Meta

* Code: `git clone git://github.com/rocketjob/rocketjob.git`
* Home: <https://github.com/rocketjob/rocketjob>
* Bugs: <http://github.com/rocketjob/rocketjob/issues>
* Gems: <http://rubygems.org/gems/rocketjob>

This project uses [Semantic Versioning](http://semver.org/).

## Author

[Reid Morrison](https://github.com/reidmorrison) :: @reidmorrison

## Contributors

* [Chris Lamb](https://github.com/lambcr)

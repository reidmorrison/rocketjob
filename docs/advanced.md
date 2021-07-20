---
layout: default
---

# Rocket Job Programmers Guide - Advanced Topics

#### Table of Contents
* [Concurrency](#concurrency)
* [Architecture](#architecture)
* [Extensibility](#extensibility)

---
## Concurrency

[Rocket Job][0] uses a thread per worker. Benefits of this approach:

* Uses less memory than forked processes.
    * Compiled ruby code is declared per process.
    * Can cache data in memory that is shared by several worker threads.
* More efficient and performs faster than forking processes.
* A single management thread can monitor all the worker threads, and perform heartbeats for
  the entire process.

Each worker is completely independent of each other so that it can run as fast as is possible with Ruby.

Concurrency Notes:

* Avoid modifying any global variables since they could be accessed by 2 worker threads at the same time.
    * Only update instance variables, or use [Sync Attr][2].
    * Verify that any cache being used is thread-safe.
* To lazy load class variables use [Sync Attr][2].
    * For example, loading configuration files etc.

## Architecture

RocketJob uses [MongoDB][3] to do "in-place" processing of a job. A job is only created
once and stored entirely as a single document in [MongoDB][3]. [MongoDB][3] is highly concurrent,
allowing all CPU's to be used if needed to scale out workers. [MongoDB][3] is not
only memory resident for performance, it can also write older data to disk, or
when there is not enough physical memory to hold all of the data.

This means that all information relating to a job is held in one document:

* State: queued, running, failed, aborted, or completed
* Percent Complete
* User defined attributes
* etc..

The status of any job is immediately visible in the [Rocket Job Mission Control][1] web
interface, without having to update some other data store since the job only lives
in one place.

The single document approach for the job is possible due to a very efficient
modify-in-place feature in [MongoDB][3] called [`find_and_modify`](http://docs.mongodb.org/manual/reference/command/findAndModify/)
that allows jobs to be efficiently assigned to any one of hundreds of available
workers without the locking issues that befall relational databases.

### Reliable

If a worker process crashes while processing a job, the job remains in the queue and is never lost.
When the _worker_ instance is destroyed / cleaned up its running jobs are re-queued and will be processed
by another _worker_.

### Scalable

As workload increases greater throughput can be achieved by adding more servers. Each server
adds more CPU, Memory and local disk to process more jobs.

[Rocket Job][0] scales linearly, meaning doubling the worker servers should double throughput.
Bottlenecks tend to be databases, networks, or external suppliers that are called during job
processing.

Additional database slaves can be added to scale for example, MySQL, and/or Postgres.
Then configuring the job workers to read from the slaves helps distribute the load.
Use [ActiveRecord Slave](https://github.com/rocketjob/active_record_slave) to efficiently redirect
ActiveRecord MySQL reads to multiple slave servers.

---
## Extensibility

Custom behavior can be mixed into a job.

For example create a mix-in that uses a validation to ensure that only one instance
of a job is running at a time:

~~~ruby
require 'active_support/concern'

module RocketJob
  module Concerns
    # Prevent more than one instance of this job class from running at a time
    module Singleton
      extend ActiveSupport::Concern

      included do
        validates_each :state do |record, attr, value|
          if where(state: [:running, :queued], _id: {'$ne' => record.id}).exists?
            record.errors.add(attr, 'Another instance of this job is already queued or running')
          end
        end
      end

    end
  end
end
~~~

Now `include` the above mix-in into a job:

~~~ruby
class MyJob < RocketJob::Job
  # Create a singleton job so that only one instance is ever queued or running at a time
  include RocketJob::Concerns::Singleton

  def perform
    # process data
  end
end
~~~

Queue the job, supplying the `file_name` that was declared and used in `FileJob`:

~~~ruby
MyJob.create!(file_name: 'abc.csv')
~~~

Trying to queue the job a second time will result in:

~~~ruby
MyJob.create!(file_name: 'abc.csv')
# => MongoMapper::DocumentNotValid: Validation failed: State Another instance of this job is already queued or running
~~~

[0]: http://rocketjob.io
[1]: mission_control.html
[2]: https://github.com/reidmorrison/sync_attr
[3]: https://www.mongodb.com

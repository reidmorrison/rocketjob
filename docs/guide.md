---
layout: default
---

## Rocket Job Programmers Guide

### Priority Based Processing

Jobs are processed based on the priority specified when the job is defined.
By default jobs have a priority of 50 and can range between 1 and 100, with 1 being the highest priority.

Priority based processing ensures that the workers are utilized to capacity, while meeting business
priorities, and without requiring any manual intervention or tuning of worker queues.

Example: Set the default priority for a job class:

~~~ruby
ImportJob.create!(
  file_name: 'file.csv',
  # Give this job a higher priority so that it will jump the queue
  priority:  5
)
~~~

The priority can also be changed on a per job basis at runtime via [Rocket Job Mission Control][1].

### Process the job at a later time

To run the job in the future, set `run_at` to a future time:

~~~ruby
ImportJob.create!(
  file_name: 'file.csv',
  # Only run this job 2 hours from now
  run_at:    2.hours.from_now
)
~~~

### Job retention

On completion jobs usually disappear. Jobs can be retained and viewed in [Mission Control][1].

~~~ruby
class CalculateJob < RocketJob::Job
  # Retain the job when it completes
  self.destroy_on_complete = false

  def perform
    # Perform work here
  end
end
~~~

### Job Attributes

Jobs already have several standard attributes, such as `description` and `priority`.
 
User defined attributes can be added by using the `field` keyword:

~~~ruby
class CalculateJob < RocketJob::Job
  # Retain the job when it completes
  self.destroy_on_complete = false
  
  field :username, type: String

  def perform
    logger.info "Username is #{username}"
    # Perform work here
  end
end
~~~

For more details on fields, their types, and defaults, see the [Mongoid Documentation](https://docs.mongodb.com/ruby-driver/master/tutorials/5.1.0/mongoid-documents/#fields).

### Job Result

When a job runs its result is usually the effect it has on the database, emails sent, etc. Sometimes
it is useful to keep the result in the job itself. The result can be used to take other actions, or to display
to an end user.

The `result` is a Hash that can contain a numeric result, string, array of values, or even a binary image, up to a
total document size of 16MB.

~~~ruby
class CalculateJob < RocketJob::Job
  # Don't destroy the job when it completes
  self.destroy_on_complete = false
  # Collect the output from the perform method
  self.collect_output      = true

  field :count, type: Integer

  def perform
    # The output from this method is stored in the job itself
    { calculation: count * 1000 }
  end
end
~~~

Queue the job for processing:

~~~ruby
job = CalculateJob.create!(count: 24)
~~~

Continue doing other work while the job runs, and display its result on completion:

~~~ruby
if job.reload.completed?
  puts "Job result: #{job.result}"
end
~~~

### Job Status

Status can be checked at any time:

~~~ruby
# Update the job's in memory status
job.reload

# Current state ( For example: :queued, :running, :completed. etc. )
puts "Job is: #{job.state}"

# Complete state information as displayed in mission control
puts "Full job status: #{job.status.inspect}"
~~~

### Expired jobs

Sometimes queued jobs are no longer business relevant if processing has not
started by a specific date and time.

The system can queue a job for processing, but if the workers are too busy with
other higher priority jobs and are not able to process this job by its expiry
time, then the job will be discarded without processing:

~~~ruby
ImportJob.create!(
  file_name: 'file.csv',
  # Don't process this job if it is queued for longer than 15 minutes
  expires_at: 15.minutes.from_now
)
~~~

### Queries

Aside from being able to see and change jobs through the [Rocket Job Mission Control][1]
web interface it is often useful, and even highly desirable to be able to access
the job programmatically while it is running.

To find the last job that was submitted:

~~~ruby
job = RocketJob::Job.last
~~~

To find a specific job, based on its id:

~~~ruby
job = RocketJob::Job.find('55aeaf03a26ec0c1bd00008d')
~~~

To change its priority:

~~~ruby
job = RocketJob::Job.find('55aeaf03a26ec0c1bd00008d')
job.priority = 32
job.save!
~~~

Or, to skip the extra save step, update any attribute of the job directly:

~~~ruby
job = RocketJob::Job.find('55aeaf03a26ec0c1bd00008d')
job.update_attributes(priority: 32)
~~~

How long has the last job in the queue been running for?

~~~ruby
job = RocketJob::Job.last
puts "The job has been running for: #{job.duration}"
~~~

How many `MyJob` jobs are currently being processed?

~~~ruby
count = MyJob.where(state: :running).count
~~~

Retry all failed jobs in the system:

~~~ruby
RocketJob::Job.where(state: :failed).each do |job|
  job.retry!
end
~~~

Is a job still running?

~~~ruby
job = RocketJob::Job.find('55aeaf03a26ec0c1bd00008d')

if job.completed?
  puts "Finished!"
elsif job.running?
  puts "The job is being processed by worker: #{job.server_name}"
end
~~~

For more details on querying jobs, see the [Mongoid Queries Documentation](https://docs.mongodb.com/ruby-driver/master/tutorials/5.1.0/mongoid-queries/) 

Since everything about this job is held in this one document, all
details about the job are accessible programmatically.

### Exception Handling

The exception and complete backtrace is stored in the job on failure to
aid in problem determination.

~~~ruby
if job.reload.failed?
  puts "Job failed with: #{job.exception.klass}: #{job.exception.message}"
  puts "Backtrace:"
  puts job.exception.backtrace.join("\n")
end
~~~

### Callbacks

Callbacks are available at many points in the job workflow process. These callbacks can be used
to add custom behavior at each of the points:

Perform callbacks:

* before_perform
* after_perform
* around_perform

Persistence related callbacks:

* after_initialize
* before_validation
* after_validation
* before_save
* before_create
* after_create
* after_save

Event callbacks:

* before_start
* after_start
* before_complete
* after_complete
* before_fail
* after_fail
* before_retry
* after_retry
* before_pause
* after_pause
* before_resume
* after_resume
* before_abort
* after_abort

Example: Send an email after a job starts, completes, fails, or aborts.

~~~ruby
class MyJob < RocketJob::Job
  field :email_recipients, type: Array

  after_start :email_started
  after_fail :email_failed
  after_abort :email_aborted
  after_complete :email_completed

  def perform
    puts "The file_name is #{file_name}"
  end

  private

  # Send an email when the job starts
  def email_started
    MyJob.started(email_recipients, self).deliver
  end

  def email_failed
    MyJob.failed(email_recipients, self).deliver
  end

  def email_aborted
    MyJob.aborted(email_recipients, self).deliver
  end

  def email_completed
    MyJob.completed(email_recipients, self).deliver
  end
end
~~~

Callbacks can be used to insert "middleware" into specific job classes, or for all jobs.

The `after_fail` callback can be used to automatically retry failed jobs. For example, retry the job again
in 10 minutes, or retry immediately for up to 3 times, etc...

For more details on callbacks, see the [Mongoid Callbacks Documentation](https://docs.mongodb.com/ruby-driver/master/tutorials/5.1.0/mongoid-callbacks/).

### Validations

The usual [Rails validations](http://guides.rubyonrails.org/active_record_validations.html)
are available since they are exposed by ActiveModel.

Example of `presence` and `inclusion` validations:

~~~ruby
class Job < RocketJob::Job
  field :login, type: String
  field :count, type: Integer

  validates_presence_of :login
  validates :count, inclusion: 1..100
end
~~~

See the [Active Model Validation Documentation](https://github.com/rails/rails/blob/master/activemodel/lib/active_model/validations.rb)
for more detailed information on validations that are available. 

### Cron replacement

* [Rocket Job][0] is a great replacement for all those cron jobs.
* Include the `RocketJob::Plugins::Cron` plugin into any job to turn it into a cron job.
* Set the attribute `cron_schedule` to any valid cron schedule.
* `cron_schedule` also supports an optional timezone. If not set it defaults to the local timezone.

Example, run the job every night at midnight UTC:

~~~ruby
class MyCronJob < RocketJob::Job
  include RocketJob::Plugins::Cron

  # Every night at midnight UTC
  self.cron_schedule      = '0 0 * * * UTC'

  def perform
    # Will be called every night at midnight UTC
  end
end
~~~

The `cron_schedule` will be validated when the job is saved, and is required for every job that
includes the `RocketJob::Plugins::Cron` plugin.

Benefits over regular cron:

* Easily run a Cron job immediately, via [Rocket Job Mission Control][1], by pressing the `run` button 
  under `Scheduled Jobs` or

~~~ruby
MyCronJob.first.update_attributes(run_at: nil)
~~~
* Easily change the cron schedule at any time.

~~~ruby
MyCronJob.first.update_attributes(cron_schedule: '* 1 * * * America/New_York')
~~~
* Cron job failures are viewable in [Rocket Job Mission Control][1]
* No single point of failure.
    * Linux/Unix cron is defined on a single server. If that server is unavailable for any reason
      then the cron jobs no longer run.
    * Rocket Job will run the cron jobs on any available worker.

### Extensibility

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

### High performance logging

Supports sending log messages, exceptions, and errors simultaneously to one or more of:

* File
* Bugsnag
* MongoDB
* NewRelic
* Splunk
* Syslog (TCP, UDP, & local)
* Any user definable target via custom appenders

To remove the usual impact of logging, the log writing is performed in a separate thread.
In this way the time it takes to write to one or logging destinations does _not_ slow down
active worker threads.

### Concurrency

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
    * Only update instance variables, or use [Sync Attr][5].
    * Verify that any cache being used is thread-safe.
* To lazy load class variables use [Sync Attr][5].
    * For example, loading configuration files etc.

### Architecture

RocketJob uses [MongoDB][6] to do "in-place" processing of a job. A job is only created
once and stored entirely as a single document in [MongoDB][6]. [MongoDB][6] is highly concurrent,
allowing all CPU's to be used if needed to scale out workers. [MongoDB][6] is not
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
modify-in-place feature in [MongoDB][6] called [`find_and_modify`](http://docs.mongodb.org/manual/reference/command/findAndModify/)
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

## Reference

* [API Reference](http://www.rubydoc.info/gems/rocketjob/)

### [Next: Batch Processing ==>](batch.html)

[0]: http://rocketjob.io
[1]: https://github.com/rocketjob/rocketjob_mission_control
[4]: http://rocketjob.io/pro
[5]: https://github.com/reidmorrison/sync_attr


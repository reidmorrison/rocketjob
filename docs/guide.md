---
layout: default
---

# Rocket Job Programmers Guide

#### Table of Contents

* [Writing Jobs](#writing-jobs)
* [Fields](#fields)
    * [Field Types](#field-types)
    * [Defaults](#field-defaults)
    * [Field Settings](#field-settings)
* [Business Priority](#business-priority)
* [Delayed Processing](#delayed-processing)
* [Retention](#retention)
* [Collecting Output](#collecting-output)
* [Job Status](#job-status)
* [Expired Jobs](#expired-jobs)
* [Scheduled Jobs](#scheduled-jobs)
* [Automatic Retry](#automatic-retry)
* [Singleton](#singleton)
* [Processing Window](#processing-window)
* [Automatic Restart](#automatic-restart)
* [Throttling](#throttling)
* [Transactions](#transactions)
* [Persistence](#persistence)
* [Queries](#queries)
* [Callbacks](#callbacks)
* [Validations](#validations)
* [Exception Handling](#exception-handling)
* [Writing Tests](#writing-tests)
* [Command Line Interface](#command-line-interface)
* [Logging](#logging)

---
## Writing Jobs

Jobs are written by creating a class that inherits from `RocketJob::Job` and then implements
at a minimum the `perform` method.

#### Example

Create the file `report_job.rb` in the directory `app/jobs` in a Rails application, or in the `jobs` folder
when running standalone without Rails.

~~~ruby
class ReportJob < RocketJob::Job
  def perform
    puts "Hello World" 
  end
end
~~~

Start or re-start Rocket Job servers to pull in the new code:
~~~
bundle exec rocketjob
~~~

To enqueue the job for processing:
~~~ruby
ReportJob.create!
~~~

**Note** remember to restart the Rocket Job servers anytime changes are made to a job's source code.  

#### Rails Console Example

When running Rails, start up a console and we can try out a new job directly in the console without
needing to start the Rocket Job server(s).

~~~
bundle exec rails console
~~~

Create the HelloJob in the console:
~~~ruby
class HelloJob < RocketJob::Job
  def perform
    puts "Hello World" 
  end
end
~~~

Now enter the following at the console to run the HelloJob:
~~~ruby
job = HelloJob.new
job.perform_now
# => Hello World
~~~

The method `perform_now` allows the job to be performed inline in the current process. It also does not require the
job to be saved first. This approach is used heavily in tests so that a Rocket Job server is not needed to run tests.
 
## Fields

Jobs already have several standard fields, such as `description` and `priority`.
 
User defined fields can be added by using the `field` keyword:

~~~ruby
class ReportJob < RocketJob::Job
  # Retain the job when it completes
  self.destroy_on_complete = false
  
  # Custom field called `username` with a type of `String`
  field :username, type: String

  def perform
    logger.info "Username is #{username}"
    # Perform work here
  end
end
~~~

### Field Types

Valid field types:
* Array
* Mongoid::Boolean
* Date
* DateTime
* Float
* Hash
* Integer
* BSON::ObjectId
* BSON::Binary
* Range
* Regexp
* String
* Mongoid::StringifiedSymbol
* Time
* TimeWithZone

To set the field when the job is created:
~~~ruby
job = ReportJob.create!(username: 'Jack Jones')
~~~

To retrieve the value:

~~~ruby
puts job.username
# => Jack Jones
~~~

User defined fields can also be set or retrieved within the job itself.

#### Example

~~~ruby
class ReportJob < RocketJob::Job
  # Retain the job when it completes
  self.destroy_on_complete = false
  
  # Retain the output from perform
  output_category
  
  field :username, type: String
  field :user_count, type: Integer

  def perform
    # Retrieve the supplied value
    puts username
    # Set the user_count so that it is visible after the job completes
    self.user_count = 123 
  end
end
~~~

On completion the `user_count` value can be viewed in the [Rocket Job Web Interface][1], or accessed
programmatically:

~~~ruby
job = ReportJob.completed.last
puts job.user_count
# => 123
~~~

#### Notes

* When using field type `Hash` be careful to only use strings for key names and the key names must
  not contain any `.` (periods).

~~~ruby
class ReportJob < RocketJob::Job
  self.destroy_on_complete = false
  
  field :statistics, type: Hash

  def perform
    # This will fail to save properly since the key name contains periods:
    self.statistics = { 'this.is.bad' => 20}
    
    # This will save, but the symbol key will be changed to a string in the data store. 
    # Not recommended:
    self.statistics = { :valid => 39}
    
    # This will save properly
    self.statistics = { 'valid' => 39}
  end
end
~~~

### Field Defaults

When adding a custom field it can also be assigned a default value:

~~~ruby
class ReportJob < RocketJob::Job
  self.destroy_on_complete = false
  
  field :username, type: String, default: 'Joe Bloggs'
  field :user_count, type: Integer, default: 0

  def perform
    # Display username
    puts username
    
    # Increment the user count
    self.user_count += 1 
  end
end
~~~

Create the job relying on default values:
~~~ruby
job = ReportJob.new
puts job.username
# => Joe Bloggs
~~~

Defaults can also be procs so that they can be dynamically calculated at runtime:

~~~ruby
# Sets the `report_date` by default to the date when the job was created:
field :report_date, type: Date, default: -> { Date.today }
~~~

When the default is specified with a proc or lambda, it has access to the job itself.
~~~ruby
field :report_date, type: Date, default: -> { new_record? ? Date.yesterday : Date.today }
~~~

Proc or lambda default values are applied after all other attributes are set. To apply this default
before the other attributes are set, use `pre_processed: true`
~~~ruby
field :report_date, type: Date, default: -> { new_record? ? Date.yesterday : Date.today }, pre_processed: true
~~~

**Note** that defaults are evaluated at class load time, whereas proc or lambda defaults are evaluated at runtime.
In the example below only the second one would be evaluated every time the job is created, and is usually
the intended option:

~~~ruby
field :report_date, type: Date, default: Date.today
field :report_date, type: Date, default: -> { Date.today }
~~~

### Field Settings

Rocket Job supports additional field level settings to control field behavior.

#### user_editable

By default fields are not editable in the [Rocket Job Web Interface][1]. In order to give the web interface
users the ability to edit a field both within the job and in a DirmonEntry, add `user_editable: true`

~~~ruby
field :report_date, type: Date, user_editable: true
~~~

#### copy_on_restart

The `copy_on_restart` setting is only applicable to jobs that use the `RocketJob::Plugins::Restart` plugin,
and plugins that include it, such as `RocketJob::Plugins::Cron`.

By default when a new instance of a job using the restart plugin is scheduled to run it is _not_ copied
to the new instance. In order for the value to be copied the field must be marked with: `copy_on_restart: true`

~~~ruby
field :report_date, type: Date, copy_on_restart: true
~~~

## Business Priority

Rocket Job runs jobs in business priority order. Priorities range between 1 and 100,
with 1 being the highest priority. All jobs have a priority of 50 by default.
The priority can be specified when the job is created so that each instance can be
assigned a priority at run-time. In addition the default can be set in the job itself.

Priority based processing ensures that the workers are fully utilized, utilizing business
priorities to determine which jobs should be processed in what order.

#### Example

Set the default business priority for a job class:

~~~ruby
class ReportJob < RocketJob::Job
  # Set the default business priority
  self.priority = 70

  def perform
    # Perform work here
  end
end
~~~

#### Example

Increase the business priority for one instance of a job so that it will jump the queue and process first:

~~~ruby
ReportJob.create!(priority: 5)
~~~

The priority can also be changed at runtime via the [Rocket Job Web Interface][1].

## Delayed Processing

Delay the execution of a job to a future time by setting `run_at`:

~~~ruby
ReportJob.create!(
  # Only run this job 2 hours from now
  run_at:    2.hours.from_now
)
~~~

## Retention

By default jobs are cleaned up and removed automatically from the system upon completion.
To retain completed jobs:

~~~ruby
class ReportJob < RocketJob::Job
  # Retain the job when it completes
  self.destroy_on_complete = false

  def perform
    # Perform work here
  end
end
~~~

Completed jobs are visible in the [Rocket Job Web Interface][1].

#### Note

If a job fails it is always retained. Use the `RocketJob::HousekeepingJob` to clear out failed jobs
if they are not being retried.

## Collecting Output

When a job runs its result is usually the effect it has on the database, emails sent, etc. Sometimes
it is useful to keep the result in the job itself. The result can be used to take other actions, or to display
to an end user.

~~~ruby
class ReportJob < RocketJob::Job
  # Don't destroy the job when it completes
  self.destroy_on_complete = false

  # Supply the count as an input field
  field :count, type: Integer

  # Store the output of this job in this result field:
  field :result, type: Hash

  def perform
    # The output from this method is stored in the job itself
    self.result = { calculation: count * 1000 }
  end
end
~~~

Queue the job for processing:

~~~ruby
job = ReportJob.create!(count: 24)
~~~

Continue doing other work while the job runs, and display its result on completion:

~~~ruby
if job.reload.completed?
  puts "Job result: #{job.result.inspect}"
end
~~~

## Job Status

Status can be checked at any time:

~~~ruby
# Update the job's in memory status
job.reload

# Current state ( For example: :queued, :running, :completed. etc. )
puts "Job is: #{job.state}"

# Complete state information as displayed in mission control
puts "Full job status: #{job.status.inspect}"
~~~

## Expired jobs

Sometimes queued jobs are no longer business relevant if processing has not
started by a specific date and time.

The system can queue a job for processing, but if the workers are too busy with
other higher priority jobs and are not able to process this job by its expiry
time, then the job will be discarded without processing:

#### Example 

Don't process this job if it is queued for longer than 15 minutes
~~~ruby
ReportJob.create!(expires_at: 15.minutes.from_now)
~~~

## Scheduled Jobs

Scheduled jobs are used to make jobs run on a regular schedule.
 
They are a great alternative to cron tasks since they are now visible in the [Rocket Job Web Interface][1], appear
in the failed jobs list should they fail and can be retried.
They can be also be run immediately, instead of waiting until their next scheduled time, 
by pressing the `run` button in the [Rocket Job Web Interface][1].

When a scheduled job is created, it will run at the next occurence of the `cron_schedule`. When the job completes,
or fails it is automatically re-scheduled to run at the next occurence of the `cron_schedule`. 

The next instance of a scheduled job is only created once the current one has completed. This prevents the system
from starting or running multiple instances of the same scheduled job at the same time.
For example, if the job takes 10 minutes to complete, and is scheduled to run every 5 minutes,
it will only be run every 10 minutes.                                                                             

There is no centralized scheduler or need to start schedulers anywhere, since the jobs
can be processed by any Rocket Job worker. This avoids the single point of failure (SPOF) that is common to most other
job schedulers when the server hosting the scheduler fails or is not running. 
For example, with the Linux cron, if the server on which the crontab is defined is not running at the time the 
task needs to be executed then that task will not run.                                                             

### Notes

* When a scheduled job is created it is immediately queued to run in the future. When that future time comes around 
  the job will be processed immediately, only if there are workers available to process that job.
  For example, if workers are busy working on higher priority jobs, then the scheduled job
  will only run once those jobs have completed, or their priority is lowered. 
* The job will not be scheduled to run again if it has passed its expiration, if set.
  * This allows a scheduled job to automatically destroy itself at some future date by setting `expires_at`.
* When a scheduled job fails, it creates a new scheduled instance and then clears out the `cron_schedule`
  in the failed instance. That way it will not create yet another scheduled instance when it is retried.

#### Example

Create a scheduled job to run at 1am UTC every day:                                                            
                                                                                                                  
~~~ruby
class MyCronJob < RocketJob::Job                                                                                  
  include RocketJob::Plugins::Cron                                                                                
                                                                                                                  
  # Set the default cron_schedule                                                                                 
  self.cron_schedule = "0 1 * * * UTC"                                                                            
                                                                                                                  
  def perform                                                                                                     
    puts "DONE"                                                                                                   
  end                                                                                                             
end                            
~~~                                                                                   
                                                                                                                  
Queue the job for processing using the default cron_schedule specified above.                                   
~~~ruby
MyCronJob.create!
~~~

Once a scheduled job has been queued for processing it should not be created again. In Rails
a common technique is to use a migration to create the scheduled job in each environment.

#### Example

Rails migration to create a schedule job:                                                  

~~~ruby
class CreateMyCronJob < ActiveRecord::Migration
  def up
    MyCronJob.create
  end

  def down
    MyCronJob.delete_all
  end
end
~~~                                                        

#### Example

A job that can be run at regular intervals, and can also be used to run on an ad-hoc basis:
                       
~~~ruby                                                                                                                  
class ReportJob < RocketJob::Job                                                                                  
  # Do not set a default cron_schedule so that the job can also be used for ad-hoc work.                          
  include RocketJob::Plugins::Cron                                                                                
                                                                                                                  
  field :start_date, type: Date                                                                                   
  field :end_date,   type: Date                                                                                   
                                                                                                                  
  def perform                                                                                                     
    # Uses `scheduled_at` to take into account any possible delays.                                               
    self.start_at ||= scheduled_at.beginning_of_week.to_date                                                      
    self.end_at   ||= scheduled_at.end_of_week.to_date                                                            
                                                                                                                  
    puts "Running report, starting at #{start_date}, ending at #{end_date}"                                       
  end                                                                                                             
end    
~~~                                                                                                           
                                                                                                                  
Create a scheduled instance of the job by setting the `cron_schedule`:                                                           
~~~ruby
ReportJob.create!(cron_schedule: '0 1 * * * America/New_York')                                                    
~~~
                                                                
Create an ad-hoc instance of the job by leaving out the `cron_schedule`:                                                             
~~~ruby
job = ReportJob.create!(start_date: 30.days.ago, end_date: 10.days.ago)                                           
~~~
                                                                                                                  
The `cron_schedule` field is formatted as follows:                                                            
                                                                                                                  
    *    *    *    *    *    *                                                                                    
    ┬    ┬    ┬    ┬    ┬    ┬                                                                                    
    │    │    │    │    │    │                                                                                    
    │    │    │    │    │    └ Optional: Timezone, for example: 'America/New_York', 'UTC'                         
    │    │    │    │    └───── day_of_week (0-7) (0 or 7 is Sun, or use 3-letter names)                           
    │    │    │    └────────── month (1-12, or use 3-letter names)                                                
    │    │    └─────────────── day_of_month (1-31, L, -1..-31)                                                    
    │    └──────────────────── hour (0-23)                                                                        
    └───────────────────────── minute (0-59)                                                                      
                                                                                                                  
* When specifying day of week, both day 0 and day 7 is Sunday.                                                    
* Ranges & Lists of numbers are allowed.                                                                          
* Ranges or lists of names are not allowed.                                                                       
* Ranges can include 'steps', so `1-9/2` is the same as `1,3,5,7,9`.                                              
* Months or days of the week can be specified by name.                                                            
* Use the first three letters of the particular day or month (case doesn't matter).                               
* The timezone is recommended to prevent any issues with possible default timezone                                
  differences across servers, or environments.
* For the complete list of timezones, see [Wikipedia List of tz database time zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)                                                                    
* A day_of_month of `L` means the last day of the month.
                                                              
### Creating the scheduled job
    
Once a job has been written, it needs to be created so that the system will run it on it's
specified schedule. In Rails a common way to do this is via a migration.    

#### `cron_schedule` Examples

| Description   | cron_schedule
| ------------- |:-------------
| Every minute                             |`* * * * *`
| Every 10 minutes                         |`*/10 * * * *`
| Every 30 minutes on the half hour        |`0,30 * * * *`
| Every hour on the hour                   |`0 * * * *`
| |
| Every day at 2am:                        |`0 2 * * *`
| 5am and 5pm daily:                       |`0 5,17 * * *`
| Every 4 hours:                           |`* */4 * * *`
| |
| Every Month:                             |`0 0 1 * *`
| On the 5th and the 6th of every month:   |`0 0 5,6 * *`
| Last day of the month:                   |`0 12 L * *`
| 5 days before the end of the month:      |`0 0 -5 * *`
| |
| Every January:                           |`0 0 * Jan *`
| Every January, May and August:           |`0 0 * Jan,May,Aug *`
| Quarterly:                               |`0 0 1 */3 *`
| Annually:                                |`0 0 1 1 *`
| |
| Every Sunday and Friday at 5pm:          |`0 17 * * Sun,Fri`
| First Monday of every month:             |`0 12 * * Mon#1`
| Third Monday of every month:             |`0 12 * * Mon#3`
| Last Sunday of every month:              |`0 12 * * Sun#-1`
| |
| Every Sunday at 5pm:                     |`0 17 * * Sun`
| Fri, Sat & Sun at 3:30pm:                |`30 15 * * Fri,Sat,Sun`
| 4am and 5pm on Sunday and Monday only:   |`0 4,17 * * Sun,Mon`
| |
| Every night from the 5th to the 12th:    |`30 0 5-12 * *`
| 10 days before the end of the month to 5 days before the end of the month:           |`0 0 -10--5 * *`
| Every second day, 10 days before the end of the month to 5 days before the end of the month:  |`0 0 -10--2/2 * *`

To try out a new cron entry to see if it returns the expected timestamps:
~~~ruby
   Fugit::Cron.new("/5 * * * *").next_time.to_utc_time
~~~
Or, relative to a specific time:
~~~ruby
   current_time = Time.parse("2018-01-01 10:00:00")
   Fugit::Cron.new("/5 * * * *").next_time(current_time).to_utc_time
~~~

#### Example

To make a scheduled job run now:

~~~ruby
MyCronJob.queued.first.run_now!
~~~

#### Example

To change the `cron_schedule`:

~~~ruby
job = MyCronJob.queued.first
job.cron_schedule = '* 1 * * * America/New_York'
job.save!
~~~

When the `cron_schedule` is changed, it automatically recalculates the `run_at` before saving the job so 
that the change is immediate. 

### Custom Fields

When a scheduled job completes it creates a new scheduled instance to run in the future. The new instance will not
copy across the values for any of the custom fields to the new instance. 

~~~ruby
class MyCronJob < RocketJob::Job
  include RocketJob::Plugins::Cron

  self.cron_schedule      = '0 0 * * * UTC'
  
  field :name, type: String

  def perform
    # Will be called every night at midnight UTC
  end
end
~~~

When `MyCronJob` is created the `:name` field can be supplied:
~~~ruby
MyCronJob.create!(name: 'Joe Bloggs')
~~~

The first run of this job will use the `:name`, but when the new instance is scheduled
the value is lost.

To retain field values between instances of scheduled jobs add `copy_on_restart: true`:

~~~ruby
class MyCronJob < RocketJob::Job
  include RocketJob::Plugins::Cron

  self.cron_schedule      = '0 0 * * * UTC'
  
  # Retain the fields value between scheduled instances
  field :name, type: String, copy_on_restart: true

  def perform
    # Will be called every night at midnight UTC
  end
end
~~~

## Automatic Retry

Should a job fail it is often convenient to have the job automatically retry itself without any manual or 
human intervention.

Add the `RocketJob::Plugins::Retry` plugin to a job to have it automatically retry on failure.

#### Example

~~~ruby
class ReportJob < RocketJob::Job
  include RocketJob::Plugins::Retry

  def perform
    # Perform work here
  end
end
~~~

### Retry attempts

The default number of attempts before giving up is 25. 
It is configurable by setting the `retry_limit` attribute. 

~~~ruby
class ReportJob < RocketJob::Job
  include RocketJob::Plugins::Retry
  
  # Set the maximum number of times a job should be retried before giving up.
  self.retry_limit = 3

  def perform
    # Perform work here
  end
end
~~~

#### Notes
- When a job is retried it is scheduled to run again in the future. As a result the job will appear as `queued`
  or `running` and not `failed` in the Web Management Interface.
- The job will not be retried if:
   - it has expired.
   - it fails validations when the retry is attempted. An error is logged and the job is not retried.
   - The number of retry counts has been exceeded.
 - To see the number of times a job has failed so far:
     job.failure_count
- When a job is retried its exception is logged and the job's `exception` attribute is cleared out.

## Singleton

Singleton ensures that only one instance of a job is `running`, `queued`, or `paused`.

Add the `RocketJob::Plugins::Singleton` plugin to a job to make it a singleton.

#### Example
~~~ruby
class ReportJob < RocketJob::Job
  include RocketJob::Plugins::Singleton
  
  def perform
    # Perform work here
  end
end
~~~

## Processing Window

Ensure that a job will only run between certain hours of the day, regardless of when it was
created/enqueued. Useful for creating a job now that should only be processed later during a
specific time window. If the time window is already active the job is able to be processed
immediately.

#### Examples

- Process this job on Monday's between 8am and 10am. 
- Run this job on the 1st of every month from midnight for the entire day.

Since the cron schedule supports time zones it is easy to setup jobs to run at UTC or any other time zone.

#### Example
~~~ruby
# Only run the job between the hours of 8:30am and 8:30pm. If it is after 8:30pm schedule
# it to run at 8:30am the next day.
class BusinessHoursJob < RocketJob::Job
  include RocketJob::Plugins::ProcessingWindow

  # The start of the processing window
  self.processing_schedule = "30 8 * * * America/New_York"

  # How long the processing window is:
  self.processing_duration = 12.hours

  def perform
    # Job will only run between 8:30am and 8:30pm Eastern
  end
end
~~~

Note:
- If a job is created/enqueued during the processing window, but due to busy/unavailable workers
  is not processed during the window, the current job will be re-queued for the beginning
  of the next processing window.

## Automatic Restart

Automatically starts a new instance of this job anytime it fails, aborts, or completes.

Notes:
* Restartable jobs automatically abort if they fail. This prevents the failed job from being retried.
  - To disable this behavior, add the following empty method:
       def rocket_job_restart_abort
       end
* On destroy this job is destroyed without starting a new instance.
* On Abort a new instance is created.
* Include `RocketJob::Plugins::Singleton` to prevent multiple copies of a job from running at
  the same time.
* The job will not be restarted if:
  - A validation fails after creating the new instance of this job.
  - The job has expired.
* Only the fields that have `copy_on_restart: true` will be passed onto the new instance of this job.

#### Example

~~~ruby
class RestartableJob < RocketJob::Job
  include RocketJob::Plugins::Restart

  # Retain the completed job under the completed tab in Rocket Job Web Interface.
  self.destroy_on_complete = false

  # Will be copied to the new job on restart.
  field :limit, type: Integer, copy_on_restart: true

  # Will _not_ be copied to the new job on restart.
  field :list, type: Array, default: [1,2,3]

  # Set run_at every time a new instance of the job is created.
  after_initialize set_run_at, if: :new_record?

  def perform
    puts "The limit is #{limit}"
    puts "The list is #{list}"
    'DONE'
  end

  private

  # Run this job in 30 minutes.
  def set_run_at
    self.run_at = 30.minutes.from_now
  end
end

job = RestartableJob.create!(limit: 10, list: [4,5,6])
job.reload.state
# => :queued

job.limit
# => 10

job.list
# => [4,5,6]

# Wait 30 minutes ...

job.reload.state
# => :completed

# A new instance was automatically created.
job2 = RestartableJob.last
job2.state
# => :queued

job2.limit
# => 10

job2.list
# => [1,2,3]
~~~

## Throttling

Throttle the number of jobs of a specific class that are running at the same time.

Since it is common to run hundreds or thousands of workers it could allow jobs to
overwhelm resources causing a distributed denial of service against that resource.
In this case the job can be throttled to only allow a certain number of workers to
work on it at the same time. 

Any jobs in excess of `throttle_running_jobs` will remain in a queued state and only prcocessed
when the running number of jobs of that class drops below the value of `throttle_running_jobs`.

#### Example
~~~ruby
class MyJob < RocketJob::Job
  # Maximum number of jobs of this class to process at the same time.
  self.throttle_running_jobs = 25

  def perform
    # ....
  end
end
~~~

Notes:
- The number of running jobs will not exceed this value.
- It may appear that a job is running briefly over this limit, but then is immediately back into queued state.
  This is expected behavior and is part of the check to ensure this value is not exceeded.
  The worker grabs the job and only then verifies the throttle, this is to prevent any other worker
  from attempting to grab the job, which would have exceeded the throttle.


### Throttles Dependent Jobs

Prevent a job from running while other jobs are running.

#### Example

This job will not run if there are instances of `FirstJob` or `SecondJob` already running:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Plugins::ThrottleDependentJobs
  
  self.dependent_jobs = ["FirstJob", "SecondJob"]

  def perform
    # ....
  end
end
~~~

### Custom Throttles

Using the throttling famework, custom throttle plugins can be created.

#### Example

Do not run this job when the MySQL slave delay exceeds 5 minutes.

~~~ruby
class MyJob < RocketJob::Job
  define_throttle :mysql_throttle_exceeded?

  def perform
    # ....
  end

  private

  # Returns true if the MySQL slave delay exceeds 5 minutes
  def mysql_throttle_exceeded?
    status        = ActiveRecord::Base.connection.select_one('show slave status')
    seconds_delay = Hash(status)['Seconds_Behind_Master'].to_i
    seconds_delay >= 300
  end
end
~~~

## Transactions

Wraps every `#perform` call with an Active Record transaction / unit or work.

If the perform raises an exception it will cause any database changes to be rolled back.

For Batch Jobs the transaction is at the slice level so that the entire slice succeeds,
or is rolled back.

#### Example

~~~ruby
# Update User and create an Audit entry as a single database transaction.
# If Audit.create! fails then the user change will also be rolled back.
class MyJob < RocketJob::Job
  include RocketJob::Plugins::Transaction

  def perform
    u = User.find(name: 'Jack')
    u.age = 21
    u.save!

    Audit.create!(table: 'user', description: 'Changed age to 21')
  end
end

Performance
- On CRuby an empty transaction block call takes about 1ms.
- On JRuby an empty transaction block call takes about 55ms.

Note:
- This plugin will only be activated if ActiveRecord has been loaded first.
~~~

---
## Persistence

The regular persistence methods are commonly found in other popular frameworks.

### Job.create!

Enqueue a single job for processing.
Raises an exception if a validation error occurs.

~~~ruby
ReportJob.create!(report_date: Date.yesterday)
~~~

### Job#save!

Enqueue a new job for processing. 
Raises an exception if a validation error occurs.

~~~ruby
job = ReportJob.new
job.report_date = Date.yesterday
job.save!
~~~

Save only the changed attributes atomically.
Raises an exception if a validation error occurs.

~~~ruby
job = ReportJob.last
job.report_date = Date.today
job.save!
~~~

### Job#update_attributes!

Update the provided attributes and any other dirty fields.  
Raises an exception if a validation error occurs.

~~~ruby
job.update_attributes!(report_date: Date.yesterday)
~~~

### Job#update_attribute

Update a single attribute, bypassing validations.

~~~ruby
job.update_attribute(:report_date, Date.yesterday)
~~~

### Job#delete

Delete the job from the database _without_ running any callbacks.

~~~ruby
job.delete
~~~

### Job#destroy

Delete the job from the database while running callbacks.

~~~ruby
job.destroy
~~~

### Job.delete_all

Delete all jobs from the database for that job class _without_ running any callbacks.

~~~ruby
ReportJob.delete_all
~~~

Delete all jobs from the database _without_ running any callbacks.

~~~ruby
RocketJob::Job.delete_all
~~~

### Job.destroy_all

Delete all jobs from the database for that job class while running callbacks.

~~~ruby
ReportJob.destroy_all
~~~

Delete all jobs from the database while running any callbacks.

~~~ruby
RocketJob::Job.destroy_all
~~~

---
## Queries

Aside from being able to see and change jobs through the [Rocket Job Web Interface][1]
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
count = MyJob.running.count
~~~

Retry all failed jobs in the system:

~~~ruby
RocketJob::Job.failed.each do |job|
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

### Custom Fields

Custom fields can be used in queries to find a specific instance of a job class.

#### Example 

Find the reporting job for a specific date:

~~~ruby
class ReportJob < RocketJob::Job
  self.destroy_on_complete = false
  
  field :report_date, type: Date, default: -> { Date.today }

  def perform
    puts report_date
  end
end
~~~

~~~ruby
job = ReportJob.where(report_date: Date.yesterday).first
~~~ 

---
## Callbacks

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

#### Example

Send an email after a job starts, completes, fails, or aborts.

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

Define before and after callbacks

Before callbacks are called in the order they are defined.
After callbacks are called in the _reverse_ order to which they were defined.

For example, the order of befores and afters:
~~~
before_1
before_2
perform
after_2
after_1
~~~

Example including around callbacks:

~~~ruby
class MyJob < RocketJob::Job
  before_perform do
    puts "BEFORE 1"
  end

  around_perform do |job, block|
    puts "AROUND 1 BEFORE"
    block.call
    puts "AROUND 1 AFTER"
  end

  before_perform do
    puts "BEFORE 2"
  end

  after_perform do
    puts "AFTER 1"
  end

  around_perform do |job, block|
    puts "AROUND 2 BEFORE"
    block.call
    puts "AROUND 2 AFTER"
  end

  after_perform do
    puts "AFTER 2"
  end

  def perform
    puts "PERFORM"
    23
  end
end
~~~

Run the job now from a console, without requiring workers:
~~~ruby
MyJob.new.perform_now
~~~

Output:
~~~
BEFORE 1
AROUND 1 BEFORE
BEFORE 2
AROUND 2 BEFORE
PERFORM
AFTER 2
AROUND 2 AFTER
AFTER 1
AROUND 1 AFTER
~~~

For more details on callbacks, see the [Mongoid Callbacks Documentation](https://docs.mongodb.com/mongoid/master/tutorials/mongoid-callbacks).

---
## Validations

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
 
---
## Exception Handling

The exception and complete backtrace is stored in the job on failure to
aid in problem determination.

~~~ruby
if job.reload.failed?
  puts "Job failed with: #{job.exception.klass}: #{job.exception.message}"
  puts "Backtrace:"
  puts job.exception.backtrace.join("\n")
end
~~~

---
## Writing Tests

### In-Memory

Jobs can be created and run entirely in-memory, without being persisted.
This is useful for tests, as well as for trying out jobs in a console.
In production this technique can also be used to run a new job in a
console for diagnostic purposes without it being picked up by active workers.

Example Job:
~~~ruby
# Example job
class ReportJob < RocketJob::Job
  # Retain the job on completion
  self.destroy_on_complete = false
  
  # Retain the result returned by perform
  output_category
  
  def perform
    puts "Hello World"
    45
  end
end
~~~

Create a job instance in-memory, by calling `.new` instead of `.create!`
~~~ruby
job = ReportJob.new
~~~ 

Run the entire job in-memory by calling `#perform_now`
~~~ruby
job.perform_now
~~~ 

The job should complete successfully:
~~~ruby
job.completed?
# => 'true'
~~~
 
If the job failed in memory, inspect its attributes:
~~~ruby
p(job.attributes) if job.failed?
~~~ 

### Tests

Minitest example on how to test the above `ReportJob`

~~~ruby
require_relative 'test_helper'

class ReportJobTest < Minitest::Test
  describe ReportJob do
    # Create an in-memory instance of the ReportJob
    let(:report_job) do
      ReportJob.new
    end

    describe '#perform_now' do
      it 'returns 45' do
        # When a job is created it is immediately in queued status
        assert report_job.queued?
        
        report_job.perform_now
        
        # Job should successfully complete
        assert report_job.completed?, -> { report_job.attributes }
        
        # On completion the job retained its output value of 45
        assert_equal({'result' => 45 }, report_job.result) 
      end
    end
  end
end  
~~~

---
## Command Line Interface

RocketJob offers a command line interface for starting servers. 

#### Server

Start a server that will run 10 workers:

~~~
bundle exec rocketjob
~~~

Start a server with just 2 workers:

~~~
bundle exec rocketjob --workers 2
~~~

#### Filtering

Limit all workers in a server instance to only run `DirmonJob` and `WeeklyReportJob`

~~~
bundle exec rocketjob --filter "DirmonJob|WeeklyReportJob"
~~~

Notes:
- The filter is a regular ruby expression. 
- The regular expression needs to be appropriately escaped when invoked from a command line shell.

[0]: http://rocketjob.io
[1]: mission_control.html
[2]: https://github.com/reidmorrison/sync_attr
[3]: https://www.mongodb.com

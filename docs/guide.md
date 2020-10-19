---
layout: default
---

# Rocket Job Programmers Guide

#### Table of Contents

* [Regular Jobs](#regular-jobs)
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
* [Batch Jobs](#batch-jobs)
    * [Batch Output](#batch-output)
    * [Batch Job Throttling](#batch-job-throttling)
    * [Large File Processing](#large-file-processing)
    * [Multiple Output Files](#multiple-output-files)
    * [Error Handling](#error-handling)
    * [Reading Tabular Files](#reading-tabular-files)
    * [Writing Tabular Files](#writing-tabular-files)
* Included Jobs
    * [Housekeeping Job](#housekeeping-job)
    * [Dirmon Job](#dirmon-job)
    * [OnDemandJob](#ondemandjob)
    * [OnDemandBatchJob](#ondemandbatchjob)
* [Concurrency](#concurrency)
* [Architecture](#architecture)
* [Extensibility](#extensibility)

---
## Writing Jobs

Jobs are written by creating a class that inherits from `RocketJob::Job` and then implements
at a minimum the method perform.

Example: ReportJob

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

##### Rails Console Example

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
 
### Fields

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

#### Field Types

Valid field types:
* Array
* BigDecimal
* Boolean
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
* Symbol
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

User defined fields can also be set or retrieved within the job itself. Example:

~~~ruby
class ReportJob < RocketJob::Job
  # Retain the job when it completes
  self.destroy_on_complete = false
  
  # Retain the output from perform
  self.collect_output = true 
  
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

##### Notes

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

#### Field Defaults

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

#### Field Settings

Rocket Job supports additional field level settings to control field behavior.

##### user_editable

By default fields are not editable in the [Rocket Job Web Interface][1]. In order to give the web interface
users the ability to edit a field both within the job and in a DirmonEntry, add `user_editable: true`

~~~ruby
field :report_date, type: Date, user_editable: true
~~~

##### copy_on_restart

The `copy_on_restart` setting is only applicable to jobs that use the `RocketJob::Plugins::Restart` plugin,
and plugins that include it, such as `RocketJob::Plugins::Cron`.

By default when a new instance of a job using the restart plugin is scheduled to run it is _not_ copied
to the new instance. In order for the value to be copied the field must be marked with: `copy_on_restart: true`

~~~ruby
field :report_date, type: Date, copy_on_restart: true
~~~

### Business Priority

Rocket Job runs jobs in business priority order. Priorities range between 1 and 100,
with 1 being the highest priority. All jobs have a priority of 50 by default.
The priority can be specified when the job is created so that each instance can be
assigned a priority at run-time. In addition the default can be set in the job itself.

Priority based processing ensures that the workers are fully utilized, utilizing business
priorities to determine which jobs should be processed in what order.

Example: Set the default business priority for a job class:

~~~ruby
class ReportJob < RocketJob::Job
  # Set the default business priority
  self.priority = 70

  def perform
    # Perform work here
  end
end
~~~

Example: Increase the business priority for one instance of a job so that it will jump the queue and process first:

~~~ruby
ReportJob.create!(priority: 5)
~~~

The priority can also be changed at runtime via the [Rocket Job Web Interface][1].

### Delayed Processing

Delay the execution of a job to a future time by setting `run_at`:

~~~ruby
ReportJob.create!(
  # Only run this job 2 hours from now
  run_at:    2.hours.from_now
)
~~~

### Retention

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

##### Note

If a job fails it is always retained. Use the `RocketJob::HousekeepingJob` to clear out failed jobs
if they are not being retried.

### Collecting Output

When a job runs its result is usually the effect it has on the database, emails sent, etc. Sometimes
it is useful to keep the result in the job itself. The result can be used to take other actions, or to display
to an end user.

The `result` of a perform is a Hash that can contain a numeric result, string, array of values, or even a binary image, up to a
total document size of 16MB.

~~~ruby
class ReportJob < RocketJob::Job
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
job = ReportJob.create!(count: 24)
~~~

Continue doing other work while the job runs, and display its result on completion:

~~~ruby
if job.reload.completed?
  puts "Job result: #{job.result.inspect}"
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

Example: Don't process this job if it is queued for longer than 15 minutes
~~~ruby
ReportJob.create!(expires_at: 15.minutes.from_now)
~~~

### Scheduled Jobs

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

#### Notes

* When a scheduled job is created it is immediately queued to run in the future. When that future time comes around 
  the job will be processed immediately, only if there are workers available to process that job.
  For example, if workers are busy working on higher priority jobs, then the scheduled job
  will only run once those jobs have completed, or their priority is lowered. 
* The job will not be scheduled to run again if it has passed its expiration, if set.
  * This allows a scheduled job to automatically destroy itself at some future date by setting `expires_at`.
* When a scheduled job fails, it creates a new scheduled instance and then clears out the `cron_schedule`
  in the failed instance. That way it will not create yet another scheduled instance when it is retried.

Example, create a scheduled job to run at 1am UTC every day:                                                            
                                                                                                                  
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

Example, Rails migration to create a schedule job:                                                  

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
                                                                                                                        
Example, a job that can be run at regular intervals, and can also be used to run on an ad-hoc basis:
                       
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
                                                              
#### Creating the scheduled job
    
Once a job has been written, it needs to be created so that the system will run it on it's
specified schedule. In Rails a common way to do this is via a migration.    

#### `cron_schedule` Examples

| Description   | cron_schedule
| ------------- |:-------------
| Every minute                             |`* * * * *`
| Every 10 minutes                         |`*/10 * * * *`
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

Example, to make a scheduled job run now:

~~~ruby
MyCronJob.queued.first.run_now!
~~~

Example, to change the `cron_schedule`:

~~~ruby
job = MyCronJob.queued.first
job.cron_schedule = '* 1 * * * America/New_York'
job.save!
~~~

When the `cron_schedule` is changed, it automatically recalculates the `run_at` before saving the job so 
that the change is immediate. 

#### Custom Fields

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

### Automatic Retry

Should a job fail it is often convenient to have the job automatically retry itself without any manual or 
human intervention.

Add the `RocketJob::Plugins::Retry` plugin to a job to have it automatically retry on failure.

Example:
~~~ruby
class ReportJob < RocketJob::Job
  include RocketJob::Plugins::Retry

  def perform
    # Perform work here
  end
end
~~~

#### Retry attempts

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

### Singleton

Singleton ensures that only one instance of a job is `running`, `queued`, or `paused`.

Add the `RocketJob::Plugins::Singleton` plugin to a job to make it a singleton.

Example:
~~~ruby
class ReportJob < RocketJob::Job
  include RocketJob::Plugins::Singleton
  
  def perform
    # Perform work here
  end
end
~~~

### Processing Window

Ensure that a job will only run between certain hours of the day, regardless of when it was
created/enqueued. Useful for creating a job now that should only be processed later during a
specific time window. If the time window is already active the job is able to be processed
immediately.

Example: Process this job on Monday's between 8am and 10am.

Example: Run this job on the 1st of every month from midnight for the entire day.

Since the cron schedule supports time zones it is easy to setup jobs to run at UTC or any other time zone.

Example:
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

### Automatic Restart

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

Example:

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

### Throttling

Throttle the number of jobs of a specific class that are running at the same time.

Since it is common to run hundreds or thousands of workers it could allow jobs to
overwhelm resources causing a distributed denial of service against that resource.
In this case the job can be throttled to only allow a certain number of workers to
work on it at the same time. 

Any jobs in excess of `throttle_running_jobs` will remain in a queued state and only prcocessed
when the running number of jobs of that class drops below the value of `throttle_running_jobs`.

Example:
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

#### Custom Throttles

Using the throttling famework, custom throttle plugins can be created.

Example:

~~~ruby
# Do not run this job when the MySQL slave delay exceeds 5 minutes.
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

### Transactions

Wraps every `#perform` call with an Active Record transaction / unit or work.

If the perform raises an exception it will cause any database changes to be rolled back.

For Batch Jobs the transaction is at the slice level so that the entire slice succeeds,
or is rolled back.

Example:
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
### Persistence

The regular persistence methods are commonly found in other popular frameworks.

##### Job.create!

Enqueue a single job for processing.
Raises an exception if a validation error occurs.

~~~ruby
ReportJob.create!(report_date: Date.yesterday)
~~~

##### Job#save!

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

##### Job#update_attributes!

Update the provided attributes and any other dirty fields.  
Raises an exception if a validation error occurs.

~~~ruby
job.update_attributes!(report_date: Date.yesterday)
~~~

##### Job#update_attribute

Update a single attribute, bypassing validations.

~~~ruby
job.update_attribute(:report_date, Date.yesterday)
~~~

##### Job#delete

Delete the job from the database _without_ running any callbacks.

~~~ruby
job.delete
~~~

##### Job#destroy

Delete the job from the database while running callbacks.

~~~ruby
job.destroy
~~~

##### Job.delete_all

Delete all jobs from the database for that job class _without_ running any callbacks.

~~~ruby
ReportJob.delete_all
~~~

Delete all jobs from the database _without_ running any callbacks.

~~~ruby
RocketJob::Job.delete_all
~~~

##### Job.destroy_all

Delete all jobs from the database for that job class while running callbacks.

~~~ruby
ReportJob.destroy_all
~~~

Delete all jobs from the database while running any callbacks.

~~~ruby
RocketJob::Job.destroy_all
~~~

---
### Queries

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

##### Custom Fields

Custom fields can be used in queries to find a specific instance of a job class.

Example: Find the reporting job for a specific date:

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
 
---
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
  self.collect_output = true   
  
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

---
## Logging

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

---
## Batch Jobs

Regular jobs run on a single worker. In order to scale up and use all available workers
it is necessary to break up the input data into "slices" so that different parts of the job
can be processed in parallel.

Jobs that include `RocketJob::Batch` break their work up into slices so that many workers can work
on the individual slices at the same time. Slices take a large and unwieldy job and break it up
into _bite-size_ pieces that can be processed a slice at a time by the workers.

Since batch jobs consist of lots of smaller slices the job can be paused, resumed, or even aborted as a whole.
If there are any failed slices when the job finishes, they can all be retried by retrying the job itself.

For example, using the default `slice_size` of 100, and the uploaded file contains 1,000,000 lines, 
then the job will contain 10,000 slices.

Slices are made up of records, 100 by default, each record usually refers to a line or row in a file, but is any
valid BSON object for which work is to be performed.

A running batch job will be interrupted if a new job with a higher priority is queued for
processing.  This allows low priority jobs to use all available resources until a higher
priority job arrives, and then to resume processing once the higher priority job is complete.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # Number of lines/records for each slice
  self.slice_size          = 100

  # Keep the job around after it has finished
  self.destroy_on_complete = false

  # Collect any output from the job
  self.collect_output      = true

  def perform(line)
    # Work on a single record at a time across many workers
  end
end
~~~

Queue the job for processing:

~~~ruby
# Words would come from a database query, file, etc.
words = %w(these are some words that are to be processed at the same time on many workers)

job = ReverseJob.new

# Load words as individual records for processing into the job
job.upload do |records|
  words.each do |word|
    records << word
  end
end

# Queue the job for processing
job.save!
~~~

### Batch Output

Display the output from the above batch:

~~~ruby
# Display the results that were returned
job.output.each do |slice|
  slice.each do |record|
    # Display each record returned from job
    puts record
  end
end
~~~

### Output Ordering

The order of the slices and records is exactly the same as the order in which the records were uploaded into the job. 
This makes it easy to correlate an input record with its corresponding output record.

There are cases however where the exact input and output record ordering can be changed:
- When an input file has a header row, for example CSV, but the output file does not require one, for example JSON or XML.
    - In this case the output file is just missing the header row, so every record / line will be off by 1.
- By specifying `self.collect_nil_output = false` on the job it skips any records for which `nil` was returned by
  the `perform` method. 

### Job Completion

The output from a job can be queried at any time, but will be incomplete until the job has completed processing.

To programatically wait for a job to complete processing:

~~~ruby
loop do
  sleep 1
  job.reload
  break unless job.running? || job.queued?
  puts "Job is still #{job.state}"
end
~~~


### Large File Processing

Batch jobs can process very large files. Entire files are uploaded into a Job for processing
and automatically broken up into slices for workers to process.

Queue the job for processing:

~~~ruby
job = ReverseJob.new
# Upload a file into the job for processing
job.upload('myfile.txt')
job.save!
~~~

Once the job has completed, download the output records into a file:

~~~ruby
# Download the output and compress the output into a GZip file
job.download('reversed.txt.gz')
~~~

Rocket Job has built-in support for reading and writing

* `Zip` files
* `GZip` files
* files encrypted with [Symmetric Encryption][3]
* delimited files
    * Windows CR/LF text files
    * Linux text files
    * Auto-detects Windows or Linux line endings
    * Any custom delimiter
* files with fixed length records

Note:

* In order to read and write `Zip` on CRuby, add the gem `rubyzip` to your `Gemfile`.
* Not required with JRuby since it will use the native `Zip` support built into Java

### Uploading data

Rocket Job uploads the data for the job into a unique Mongo Collection for every batch job. During processing
the slices are removed from this collection as soon as they are processed.

Failed slices remain in the collection and are marked as failed so that they can be investigated or retried.

Benefits of uploading data into the job:
- Does not require access across all of the workers to the original file or data during processing.
- The file can be decompressed and / or unencrypted before it is broken up into slices.
- Does not require a separate data store to hold the jobs input data.
- Rocket Job transparently takes care of the storage and retrieval of the uploaded data.
- Since a slice now has state, it can be failed, and holds the exception that occurred when trying to process that slice.
- Each slice that is being processed contains the name of the worker currently processing it.  

Data can be uploaded into a batch job from many sources:
- File.
- Active Record query.
- Mongoid query.
- A block of code.

#### Uploading Files

Upload every line in a file as records into the job for processing.

Returns the number of lines uploaded into the job as an `Integer`.

Parameters

- `file_name_or_io` `[String | IO]`
    - Full path and file name to stream into the job.
    - Or, an IOStream that responds to: `read`

- `streams` `[Symbol|Array]`
    - Streams to convert the data whilst it is being read.
    - When nil, the file_name extensions will be inspected to determine what
      streams should be applied.
    - Default: nil

- `delimiter` `[String]`
    - Line / Record delimiter to use to break the stream up into records
      - Any string to break the stream up by
      - The records when saved will not include this delimiter
    - Default: nil
      - Automatically detect line endings and break up by line
      - Searches for the first "\r\n" or "\n" and then uses that as the
        delimiter for all subsequent records

- `buffer_size` `[Integer]`
    - Size of the blocks when reading from the input file / stream.
    - Default: 65536 ( 64K )

- `encoding` `[String|Encoding]`
    - Encode returned data with this encoding.
      - 'US-ASCII':   Original 7 bit ASCII Format
      - 'ASCII-8BIT': 8-bit ASCII Format
      - 'UTF-8':      UTF-8 Format
      - Etc.
    - Default: 'UTF-8'

- `encode_replace` `[String]`
    - The character to replace with when a character cannot be converted to the target encoding.
    - nil: Don't replace any invalid characters. Encoding::UndefinedConversionError is raised.
    - Default: nil

- `encode_cleaner` `[nil|symbol|Proc]`
    - Cleanse data read from the input stream.
    - `nil`: No cleansing
    - `:printable`: Cleanse all non-printable characters except \r and \n
    - Proc / lambda:    Proc to call after every read to cleanse the data
    - Default: :printable

- `stream_mode` `[:line | :array | :hash]`
    - `:line`
      - Uploads the file a line (String) at a time for processing by workers.
    - `:array`
      - Parses each line from the file as an Array and uploads each array for processing by workers.
    - `:hash`
      - Parses each line from the file into a Hash and uploads each hash for processing by workers.
    - See `IOStream#each`.
    - Default: `:line`

Example, load plain text records from a file

~~~ruby
job.upload('hello.csv')
~~~

Example:

Load plain text records from a file, stripping all non-printable characters,
as well as any characters that cannot be converted to UTF-8
~~~ruby
job.upload('hello.csv', encode_cleaner: :printable, encode_replace: '')
~~~

Example: Zip
~~~ruby
job.upload('myfile.csv.zip')
~~~

Example: Encrypted Zip

~~~ruby
job.upload('myfile.csv.zip.enc')
~~~
Example: Explicitly set the streams

~~~ruby
job.upload('myfile.ze', streams: [:zip, :enc])
~~~

Example: Supply custom options
~~~ruby
job.upload('myfile.csv.enc', streams: :enc])
~~~

Example: Extract streams from filename but write to a temp file

~~~ruby
streams = IOStreams.streams_for_file_name('myfile.gz.enc')
t = Tempfile.new('my_project')
job.upload(t.to_path, streams: streams)
~~~

Notes:
- By default all data read from the file/stream is converted into UTF-8 before being persisted. This
  is recommended since Mongo only supports UTF-8 strings.
- When zip format, the Zip file/stream must contain only one file, the first file found will be
  loaded into the job
- If an io stream is supplied, it is read until it returns nil.
- Only call from one thread at a time per job instance.
- CSV parsing is slow, so it is left for the workers to do.

See: [IOStreams](https://github.com/rocketjob/iostreams) for more information on supported file types and conversions
that can be applied during calls to `upload` and `download`.

#### Active Record Queries

Upload results from an Active Record Query into a batch job.                             
                                                                                   
Parameters                                                                             
- `column_names`                                                                   
  - When a block is not supplied, supply the names of the columns to be returned   
    and uploaded into the job.                                                      
  - These columns are automatically added to the select list to reduce overhead. 
  - Default: `:id`   
                                                                                   
If a Block is supplied it is passed the model returned from the database and should
return the work item to be uploaded into the job.                                  
                                                                                   
Returns [Integer] the number of records uploaded                                   
                                                                                   
Example: Upload id's for all users
~~~ruby                                                 
arel = User.all                                                                  
job.upload_arel(arel)                                         
~~~
                                                                           
Example: Upload selected user id's
~~~ruby
arel = User.where(country_code: 'US')
job.upload_arel(arel)                                         
~~~
                                                                                   
Example: Upload user_name and zip_code                                             
~~~ruby                                                 
arel = User.where(country_code: 'US')                                            
job.upload_arel(arel, :user_name, :zip_code)                  
~~~
 
#### Mongoid Queries 

Upload the result of a MongoDB query to the input collection for processing.
Useful when an entire MongoDB collection, or part thereof needs to be
processed by a job.

Returns [Integer] the number of records uploaded

If a Block is supplied it is passed the document returned from the
database and should return a record for processing.

If no Block is supplied then the record will be the :fields returned
from MongoDB.

Notes:
  - This method uses the collection directly and not the Mongoid document to
    avoid the overhead of constructing a model with every document returned
    by the query.
  - The Block must return types that can be serialized to BSON.
    - Valid Types: `Hash | Array | String | Integer | Float | Symbol | Regexp | Time`
    - Invalid: `Date`, etc.
    - With a `Hash`, the keys must be strings and not symbols.

Example: Upload document ids

~~~ruby
criteria = User.where(state: 'FL')
job.upload_mongo_query(criteria)
~~~

Example: Specify one or more columns other than just the document id to upload:

~~~ruby
criteria = User.where(state: 'FL')
job.upload_mongo_query(criteria, :zip_code)
~~~

#### Upload Block

When a block is supplied, it is given a record stream into which individual records can be written.

Upload by writing records one at a time to the upload stream.
~~~ruby
job.upload do |writer|
  10.times { |i| writer << i }
end
~~~

### Batch Job Throttling

Throttle the number of workers that can work on a batch job instance at any time.

Limiting can be used when too many concurrent workers are:

* Overwhelming a third party system by calling it too frequently.
* Impacting the online production systems by writing too much data too quickly to the master database.

Worker limiting also allows batch jobs to be processed concurrently instead of sequentially.

The `throttle_running_workers` throttle can be changed at any time, even while the job is running to
either increase or decrease the number of workers working on that job.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # No more than 10 workers should work on this job at a time
  self.throttle_running_workers = 10

  def perform(line)
    line.reverse
  end
end
~~~

### Multiple Output Files

A single batch job can also create multiple output files by categorizing the result
of the perform method.

This can be used to output one file with results from the job and another for
outputting for example the lines that were too short.

~~~ruby
class MultiFileJob < RocketJob::Job
  include RocketJob::Batch

  self.collect_output      = true
  self.destroy_on_complete = false
  # Register additional `:invalid` output category for this job
  self.output_categories   = [ :main, :invalid ]

  def perform(line)
    if line.length < 10
      # The line is too short, send it to the invalid output collection
      Result.new(line, :invalid)
    else
      # Reverse the line ( default output goes to the :main output collection )
      line.reverse
    end
  end
end
~~~

When complete, download the results of the batch into 2 files:

~~~ruby
# Download the regular results
job.download('reversed.txt.gz')

# Download the invalid results to a separate file
job.download('invalid.txt.gz', category: :invalid)
~~~

### Error Handling

Since a Batch job breaks a single job into slices, individual records within
slices can fail while others are still being processed.

~~~ruby
# Display the exceptions for failed slices:
job = RocketJob::Job.find('55bbce6b498e76424fa103e8')
job.input.each_failed_record do |record, slice|
  p slice.exception
end
~~~

Once all slices have been processed and there are only failed slices left, then the job as a whole
is failed.

### Reading Tabular Files

Very often received data is in a format very similar to that of a spreadsheet
with rows and columns, such as CSV, or Excel files. 
Usually the first row is the header that describes what each column contains.
The remaining rows are the actual data for processing.

Include the `RocketJob::Batch::Tabular::Input` plugin so that tabular files such as csv and Excel are automatically
parsed prior to being passed into the perform method. Since the plugin parses each row prior to `perform` being called,
a Hash will be passed as the first argument to `perform`, instead of the raw csv line.

This `Hash` consists of the header field names as keys and the values that were received for the specific row 
in the file.

~~~ruby
class TabularJob < RocketJob::Job
  include RocketJob::Batch
  include RocketJob::Batch::Tabular::Input
  
  def perform(row)
  #  row is now a hash because the tabular plugin already parsed the csv data: 
  #  {
  #     "first_field" => 100,
  #     "second"      => 200,
  #     "third"       => 300
  #   }
  end
end
~~~

Upload a file into the job for processing
~~~ruby
job = TabularJob.new
job.upload('my_really_big_csv_file.csv')
job.save!
~~~

Notes:
- In the above example, the file is uploaded into the job in its entirety before the job is saved.
- It is possible to save the job prior to uploading the file, but if the file upload fails workers will have already
  processed much of the data that was uploaded.
- The file is uploaded using a stream so that the entire file is not loaded into memory. This allows extremely
  large files to be uploaded with minimal memory overhead.

### Writing Tabular Files

Jobs can also output tabular data such as CSV files. Instead of making the job deal with CSV
transformations directly, it can include the `RocketJob::Batch::Tabular::Output` plugin:

~~~ruby
class ExportUsersJob < RocketJob::Job
  include RocketJob::Batch
  include RocketJob::Batch::Tabular::Output
  
  # Columns to include in the output file
  self.tabular_output_header = ["login", "last_login"]
  
  def perform(login)
    u = User.find_by(login: login)
    # Return a Hash that tabular will render as CSV
    {
      "login"      => u.login,
      "last_login" => u.updated_at
    }
  end
end
~~~

Upload a file into the job for processing
~~~ruby
job = ExportUsersJob.new
# Upload list of locked user ids to export.
job.upload do |io|
  User.where(locked: true).select(:id) do |u|
    io << u.id
  end
end
job.save!
~~~

Once the job has completed, export the output:
~~~ruby
job.download("output.csv")
~~~

Sample contents of `output.csv`:
~~~csv
login,last_login
jbloggs,2019-02-11 05:43:20
kadams,2019-01-12 01:20:20
~~~

#### Subset

Tabular can be used to include a subset of columns from a larger dataset:

~~~ruby
class ExportUsersJob < RocketJob::Job
  include RocketJob::Batch
  include RocketJob::Batch::Tabular::Output
  
  # Columns to include in the output file
  self.tabular_output_header = ["login", "last_login"]
  
  def perform(login)
    u = User.find_by(login: login)
    # Return a Hash of all available attributes from which it will extract
    # the "login", "last_login" columns.
    u.attributes 
  end
end
~~~

Another benefit with the above approach is that the list of output columns can be overridden 
when the job is created:
~~~ruby
# Make the job output a CSV file with the "login", "last_login", "name", and "state" columns.
job = ExportUsersJob.new(tabular_output_header: ["login", "last_login", "name", "state"])
~~~

Once the job has completed, export the output:
~~~ruby
job.download("output.csv")
~~~

Sample contents of `output.csv`:
~~~csv
login,last_login,name,state
jbloggs,2019-02-11 05:43:20,Joe Bloggs,FL
kadams,2019-01-12 01:20:20,Kevin Adams,TX
~~~

---
## Included Jobs

Rocket Job comes packaged with select jobs ready to run. 

### Housekeeping Job

The Housekeeping Job cleans up old jobs to free up disk space.

Since keeping jobs around uses up disk storage space it is necessary to remove
old jobs from the system. In particular jobs that have `self.destroy_on_complete = false`
need to be cleaned up using the Housekeeping Job.

Retention periods are specific to each state so that for example completed
jobs can be cleaned up before jobs that have failed.

To create the housekeeping job, using the defaults:
~~~ruby
RocketJob::Jobs::HousekeepingJob.create!
~~~

The default retention periods for the housekeeping job:

|State|Retention Period
|:---:|:---:
|Aborted| 7 days
|Completed| 7 days
|Failed| 14 days
|Paused| never
|Queued| never

To create the housekeeping job with the same values as the default:

~~~ruby
  RocketJob::Jobs::HousekeepingJob.create!(
    aborted_retention:   7.days,
    completed_retention: 7.days,
    failed_retention:    14.days,
    paused_retention:    nil,
    queued_retention:    nil
  )
~~~

Remove aborted jobs after 1 day, completed jobs after 30 minutes and disable the removal of failed jobs:

~~~ruby
  RocketJob::Jobs::HousekeepingJob.create!(
    aborted_retention:   1.day,
    completed_retention: 30.minutes,
    failed_retention:    nil
  )
~~~

**Note**: The housekeeping job uses the singleton plugin and therefore only allows 
  one instance to be active at any time.

### Dirmon Job

The Dirmon job monitors folders for files matching the criteria specified in each DirmonEntry.

* The first time Dirmon runs it gathers the names of files in the monitored
  folders.
* On completion Dirmon kicks off a new Dirmon job passing it the list
  of known files.
* On each subsequent Dirmon run it checks the size of each file against the
  previous list of known files, and only if the file size has not changed
  the corresponding job is started for that file.
* If the job implements #upload, that method is called
  and then the file is deleted, or moved to the archive_directory if supplied

* Otherwise, the file is moved to the supplied archive_directory (defaults to
  `_archive` in the same folder as the file itself. The absolute path and
  file name of the archived file is passed into the job as either
  `upload_file_name` or `full_file_name`.

Note:
- Jobs that do not implement #upload _must_ have either `upload_file_name` or `full_file_name` as an attribute.

With RocketJob Pro, the file is automatically uploaded into the job itself
using the job's #upload method, after which the file is archived or deleted
if no archive_directory was specified in the DirmonEntry.

To start Dirmon for the first time
~~~ruby
RocketJob::Jobs::DirmonJob.create!
~~~

By default Dirmon only checks for files every 5 minutes, to change this interval to 60 seconds:

~~~ruby
RocketJob::Jobs::DirmonJob.create!(check_seconds: 60)
~~~

If another DirmonJob instance is already queued or running, then the create
above will fail with:
  MongoMapper::DocumentNotValid: Validation failed: State Another instance of this job is already queued or running

Or to start DirmonJob and ignore errors if already running
~~~ruby
RocketJob::Jobs::DirmonJob.create
~~~

### OnDemandJob

Job to dynamically perform ruby code on demand,

Create or schedule a generalized job for one off fixes or cleanups.


Example: Iterate over all rows in a table:
~~~ruby
code = <<~CODE
  User.unscoped.all.order('updated_at DESC').each |user|
    user.cleanse_attributes!
    user.save!
  end
CODE

RocketJob::Jobs::OnDemandJob.create!(
  code:          code,
  description:   'Cleanse users'
)
~~~

Example: Test job in a console:
~~~ruby
code = <<~CODE
  User.unscoped.all.order('updated_at DESC').each |user|
    user.cleanse_attributes!
    user.save!
  end
CODE

job = RocketJob::Jobs::OnDemandJob.new(code: code, description: 'cleanse users')
job.perform_now
~~~

Example: Pass input data:
~~~ruby
code = <<~CODE
  puts data['a'] * data['b']
CODE

RocketJob::Jobs::OnDemandJob.create!(
  code: code,
  data: {'a' => 10, 'b' => 2}
)
~~~

Example: Retain output:
~~~ruby
code = <<~CODE
  {'value' => data['a'] * data['b']}
CODE

RocketJob::Jobs::OnDemandJob.create!(
  code:           code,
  collect_output: true,
  data:           {'a' => 10, 'b' => 2}
)
~~~
Example: Schedule the job to run nightly at 2am Eastern:

~~~ruby
RocketJob::Jobs::OnDemandJob.create!(
  cron_schedule: '0 2 * * * America/New_York',
  code:          code
)
~~~

Example: Change the job priority, description, etc.

~~~ruby
RocketJob::Jobs::OnDemandJob.create!(
  code:          code,
  description:   'Cleanse users',
  priority:      30
)
~~~~

Example: Automatically retry up to 5 times on failure:
~~~ruby
RocketJob::Jobs::OnDemandJob.create!(
  retry_limit: 5,
  code:        code
)
~~~

### OnDemandBatchJob

Job to dynamically perform ruby code on demand as a Batch,

Often used for data correction or cleansing.

Example: Iterate over all rows in a table:
~~~ruby
code = <<-CODE
  if user = User.find(row)
    user.cleanse_attributes!
    user.save(validate: false)
  end
CODE
job  = RocketJob::Jobs::OnDemandBatchJob.new(code: code, description: 'cleanse users')
arel = User.unscoped.all.order('updated_at DESC')
job.record_count = input.upload_arel(arel)
job.save!
~~~

Console Testing:
~~~ruby
code = <<-CODE
  if user = User.find(row)
    user.cleanse_attributes!
    user.save(validate: false)
  end
CODE
job  = RocketJob::Jobs::OnDemandBatchJob.new(code: code, description: 'cleanse users')

# Run against a sub-set using a limit
arel = User.unscoped.all.order('updated_at DESC').limit(100)
job.record_count = job.input.upload_arel(arel)

# Run the subset directly within the console
job.perform_now
job.cleanup!
~~~

By default output is not collected, add the option `collect_output: true` to collect output.

Example:

~~~ruby
job = RocketJob::Jobs::OnDemandBatchJob(description: 'Fix data', code: code, throttle_running_workers: 5, priority: 30, collect_output: true)
~~~

Example: Move the upload operation into a before_batch.
~~~ruby
upload_code = <<-CODE
  arel = User.unscoped.all.order('updated_at DESC')
  self.record_count = input.upload_arel(arel)
CODE

code = <<-CODE
  if user = User.find(row)
    user.cleanse_attributes!
    user.save(validate: false)
  end
CODE

RocketJob::Jobs::OnDemandBatchJob.create!(
  upload_code: upload_code,
  code:        code,
  description: 'cleanse users'
)
~~~

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

### Architecture

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

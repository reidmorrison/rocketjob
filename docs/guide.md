---
layout: default
---

## Programmer's Guide
{:.no_toc}

**Contents**

* TOC
{:toc}

This guide covers the full programming interface for writing and running simple Rocket Job jobs.
For jobs that process large files in parallel across many workers, see the
[Batch Guide](batch.html). For installation and configuration, see the
[Installation guide](installation.html).

## Writing Jobs

A job is a Ruby class that inherits from `RocketJob::Job` and implements, at a minimum, a `perform`
method. The work the job does goes inside `perform`.

Create the file `report_job.rb` in `app/jobs` in a Rails application, or in the `jobs` folder when
running standalone without Rails:

~~~ruby
class ReportJob < RocketJob::Job
  def perform
    puts "Hello World"
  end
end
~~~

Start, or re-start, Rocket Job servers to pick up the new code:

~~~bash
bundle exec rocketjob
~~~

Enqueue the job for processing:

~~~ruby
ReportJob.create!
~~~

The next available worker on any server picks up the job, runs `perform`, and records the result.

**Note:** restart the Rocket Job servers any time a job's source code changes, so that the workers
load the new code.

### Running a job in a console

When running Rails, start a console to try out a job directly, without starting a Rocket Job server:

~~~bash
bundle exec rails console
~~~

Define the job in the console:

~~~ruby
class HelloJob < RocketJob::Job
  def perform
    puts "Hello World"
  end
end
~~~

Run it inline in the current process:

~~~ruby
job = HelloJob.new
job.perform_now
# => Hello World
~~~

`perform_now` runs the job inline in the current process. It does not require the job to be saved
first, and it does not need a running Rocket Job server. Validations are still run before `perform`
is called. This approach is used heavily in tests so that a server is not needed to run them.

## The Job Lifecycle

Every job moves through a set of states, driven by a state machine. Knowing the states makes the
rest of this guide, and the [web interface](mission_control.html), easier to follow.

| State       | Meaning
|:------------|:------------
| `queued`    | Created and waiting for a worker. This is the initial state. A job whose `run_at` is in the future is `queued` and considered _scheduled_.
| `running`   | A worker is currently processing the job.
| `completed` | Finished successfully. This is an end state. By default the job is then destroyed (see [Retention](#retention)).
| `failed`    | Raised an exception. Retained so it can be retried or aborted.
| `paused`    | Temporarily halted. Only [batch jobs](batch.html) (and jobs paused before they start) can be paused and later resumed.
| `aborted`   | Cancelled and cannot be resumed. This is an end state.

The transitions between these states are `start`, `complete`, `fail`, `retry`, `pause`, `resume`,
and `abort`. Each transition has a matching pair of [callbacks](#callbacks), for example
`before_start` / `after_start`.

Check the current state at any time:

~~~ruby
job.reload
job.state       # => :running
job.running?    # => true
job.completed?  # => false
~~~

## Fields

Every job already has a set of standard fields, and custom fields can be added with the `field`
keyword.

### Standard Fields

These fields exist on every job. The first group can be set when the job is created:

| Field                 | Type    | Default | Description
|:----------------------|:--------|:--------|:------------
| `description`         | String  |         | Human readable description, shown in the web interface.
| `priority`            | Integer | 50      | Business [priority](#business-priority) from 1 (highest) to 100 (lowest).
| `destroy_on_complete` | Boolean | true    | Destroy the job once it completes. See [Retention](#retention).
| `run_at`              | Time    |         | Do not run the job before this time. See [Delayed Processing](#delayed-processing).
| `expires_at`          | Time    |         | Discard the job if it has not started by this time. See [Expiry](#expiry).
| `log_level`           | Symbol  |         | Override the [log level](#logging) for this job. One of `:trace`, `:debug`, `:info`, `:warn`, `:error`, `:fatal`.

The remaining standard fields are read-only and maintained by Rocket Job itself:

| Field              | Type    | Description
|:-------------------|:--------|:------------
| `state`            | Symbol  | Current [state](#the-job-lifecycle). Do not modify directly.
| `created_at`       | Time    | When the job was created.
| `started_at`       | Time    | When processing started.
| `completed_at`     | Time    | When processing finished (also used for paused / aborted / failed times).
| `failure_count`    | Integer | Number of times the job has failed.
| `worker_name`      | String  | Name of the worker processing, or that processed, the job.
| `percent_complete` | Integer | Estimated progress from 0 to 100. A job can update this while running.
| `exception`        | Embedded | Details of the last exception, when the job has failed. See [Exception Handling](#exception-handling).

### User-Defined Fields

Add custom fields with the `field` keyword. A field has a name and a type:

~~~ruby
class ReportJob < RocketJob::Job
  # Retain the job when it completes so its fields can be inspected later
  self.destroy_on_complete = false

  # Custom field called `username` with a type of `String`
  field :username, type: String

  def perform
    logger.info "Username is #{username}"
    # Perform work here
  end
end
~~~

Set a field when the job is created:

~~~ruby
job = ReportJob.create!(username: "Jack Jones")
~~~

Retrieve the value:

~~~ruby
job.username
# => "Jack Jones"
~~~

Custom fields can also be read and set within the job itself. Set a field during `perform` to make
its value visible after the job completes:

~~~ruby
class ReportJob < RocketJob::Job
  self.destroy_on_complete = false

  field :username,   type: String
  field :user_count, type: Integer

  def perform
    # Read a supplied value
    puts username
    # Set a value so that it is visible after the job completes
    self.user_count = 123
  end
end
~~~

On completion the value can be viewed in [Mission Control](mission_control.html), or read
programmatically:

~~~ruby
job = ReportJob.completed.last
job.user_count
# => 123
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

**Note:** Ruby Symbols are deliberately not supported as a stored type. Use `String`, or
`Mongoid::StringifiedSymbol` when a value should behave like a symbol in Ruby but be stored as a
string.

**Note:** when using the `Hash` type, use only strings for key names, and key names must not contain
any `.` (periods):

~~~ruby
class ReportJob < RocketJob::Job
  self.destroy_on_complete = false

  field :statistics, type: Hash

  def perform
    # Fails to save: the key name contains periods
    self.statistics = {"this.is.bad" => 20}

    # Saves, but the symbol key is converted to a string. Not recommended:
    self.statistics = {valid: 39}

    # Saves correctly
    self.statistics = {"valid" => 39}
  end
end
~~~

### Field Defaults

A custom field can be given a default value:

~~~ruby
class ReportJob < RocketJob::Job
  self.destroy_on_complete = false

  field :username,   type: String,  default: "Joe Bloggs"
  field :user_count, type: Integer, default: 0

  def perform
    puts username
    self.user_count += 1
  end
end
~~~

~~~ruby
job = ReportJob.new
job.username
# => "Joe Bloggs"
~~~

Defaults can be procs, so they are calculated at runtime instead of class-load time:

~~~ruby
# Sets `report_date` by default to the date when the job is created:
field :report_date, type: Date, default: -> { Date.today }
~~~

When the default is a proc or lambda, it has access to the job itself:

~~~ruby
field :report_date, type: Date, default: -> { new_record? ? Date.yesterday : Date.today }
~~~

Proc and lambda defaults are applied _after_ all other attributes are set. To apply the default
_before_ the other attributes are set, use `pre_processed: true`:

~~~ruby
field :report_date, type: Date, default: -> { new_record? ? Date.yesterday : Date.today }, pre_processed: true
~~~

A plain default is evaluated once, at class-load time. A proc or lambda default is evaluated every
time a job is created, which is usually what is intended:

~~~ruby
field :report_date, type: Date, default: Date.today        # Evaluated once, when the class loads
field :report_date, type: Date, default: -> { Date.today } # Evaluated every time a job is created
~~~

### Field Settings

Fields support additional settings to control their behavior.

#### user_editable

By default, fields cannot be edited in [Mission Control](mission_control.html). To let web interface
users edit a field, both on the job and on a [DirmonEntry](dirmon.html), add `user_editable: true`:

~~~ruby
field :report_date, type: Date, user_editable: true
~~~

#### copy_on_restart

When a [scheduled job](#scheduled-jobs) creates its next instance, custom field values are not
carried across by default. Mark a field `copy_on_restart: true` to copy its value into the new
instance:

~~~ruby
field :report_date, type: Date, copy_on_restart: true
~~~

This is used by `RocketJob::Job#create_restart!`, which the [Cron](#scheduled-jobs) plugin relies on.

## Business Priority

Rocket Job runs jobs in business priority order. Priorities range from 1 to 100, where 1 is the
highest priority. Every job has a priority of 50 by default.

Priority based processing keeps workers fully utilized while ensuring business-critical work is
processed ahead of routine work.

Set the default priority for a job class:

~~~ruby
class ReportJob < RocketJob::Job
  self.priority = 70

  def perform
    # Perform work here
  end
end
~~~

Raise the priority for a single instance so that it jumps the queue:

~~~ruby
ReportJob.create!(priority: 5)
~~~

The priority can also be changed at runtime via [Mission Control](mission_control.html).

## Delayed Processing

Delay execution to a future time by setting `run_at`:

~~~ruby
ReportJob.create!(
  # Only run this job 2 hours from now
  run_at: 2.hours.from_now
)
~~~

A job whose `run_at` is in the future is _scheduled_: it stays `queued` until that time arrives, and
then runs as soon as a worker is available.

## Expiry

Sometimes a queued job is no longer relevant if processing has not started by a certain time. Set
`expires_at` and the job is discarded without processing if a worker has not picked it up by then:

~~~ruby
# Do not process this job if it is still queued 15 minutes from now
ReportJob.create!(expires_at: 15.minutes.from_now)
~~~

This is useful when workers are busy with higher priority jobs and the work would be stale by the
time it could run.

## Retention

By default, jobs are removed from the system automatically when they complete. To retain completed
jobs, set `destroy_on_complete` to false:

~~~ruby
class ReportJob < RocketJob::Job
  # Retain the job when it completes
  self.destroy_on_complete = false

  def perform
    # Perform work here
  end
end
~~~

Retained completed jobs are visible in [Mission Control](mission_control.html).

**Note:** a job that fails is always retained, regardless of `destroy_on_complete`. Use
`RocketJob::Jobs::HousekeepingJob` to clear out old failed jobs that are not being retried.

## Collecting Output

When a job runs, its result is usually a side effect: rows written to a database, emails sent, and
so on. Sometimes it is useful to keep a result on the job itself, to take further action or to
display to a user. Store it in a custom field:

~~~ruby
class ReportJob < RocketJob::Job
  # Retain the job after completion so the result can be read
  self.destroy_on_complete = false

  # Input field
  field :count, type: Integer

  # Output field
  field :result, type: Hash

  def perform
    self.result = {calculation: count * 1000}
  end
end
~~~

Queue the job:

~~~ruby
job = ReportJob.create!(count: 24)
~~~

Continue with other work, then read the result once the job has completed:

~~~ruby
if job.reload.completed?
  puts "Job result: #{job.result.inspect}"
end
~~~

## Job Status

A full status snapshot is available at any time:

~~~ruby
# Refresh the in-memory copy of the job
job.reload

# Current state, for example: :queued, :running, :completed
puts "Job is: #{job.state}"

# Complete status information, as displayed in Mission Control
puts "Full job status: #{job.status.inspect}"
~~~

`duration` returns how long the job has been running, or took to run:

~~~ruby
puts "The job has been running for: #{job.duration}"
~~~

## Scheduled Jobs

Scheduled jobs run on a regular schedule, like a crontab. They are a strong alternative to cron:
they are visible in [Mission Control](mission_control.html), they appear in the failed jobs list if
they fail and can be retried, and they can be run immediately with the `Run` button in the web
interface.

Add the `RocketJob::Plugins::Cron` plugin and set a `cron_schedule`. When a scheduled job is
created, it is queued to run at the next occurrence of the schedule. When that instance completes,
or fails, a new instance is automatically scheduled for the following occurrence.

The next instance is only created once the current one has finished, so the system never runs two
instances of the same scheduled job at once. For example, a job that takes 10 minutes but is
scheduled every 5 minutes runs every 10 minutes.

There is no centralized scheduler and no scheduler process to start. Any Rocket Job worker can run a
scheduled job, so there is no single point of failure. With a Linux cron, if the server hosting the
crontab is down when a task is due, that task is missed; Rocket Job has no such gap.

Create a scheduled job that runs at 1am UTC every day:

~~~ruby
class MyCronJob < RocketJob::Job
  include RocketJob::Plugins::Cron

  # Default cron schedule
  self.cron_schedule = "0 1 * * * UTC"

  def perform
    puts "DONE"
  end
end
~~~

Queue it using its default schedule:

~~~ruby
MyCronJob.create!
~~~

Once a scheduled job is queued it should not be created again. In Rails a common technique is a
migration that creates the scheduled job in each environment:

~~~ruby
class CreateMyCronJob < ActiveRecord::Migration[7.2]
  def up
    MyCronJob.create!
  end

  def down
    MyCronJob.delete_all
  end
end
~~~

### Ad-hoc and scheduled in one job

A single job can serve both as a scheduled job and as an on-demand job, by leaving the
`cron_schedule` unset by default and supplying it only when scheduling:

~~~ruby
class ReportJob < RocketJob::Job
  # No default cron_schedule, so the job can also be used for ad-hoc work
  include RocketJob::Plugins::Cron

  field :start_date, type: Date
  field :end_date,   type: Date

  def perform
    # Use `scheduled_at` to account for any delay in the job being picked up
    self.start_date ||= scheduled_at.beginning_of_week.to_date
    self.end_date   ||= scheduled_at.end_of_week.to_date

    puts "Running report, starting at #{start_date}, ending at #{end_date}"
  end
end
~~~

Create a scheduled instance by supplying a `cron_schedule`:

~~~ruby
ReportJob.create!(cron_schedule: "0 1 * * * America/New_York")
~~~

Create an ad-hoc instance by leaving the `cron_schedule` out:

~~~ruby
ReportJob.create!(start_date: 30.days.ago, end_date: 10.days.ago)
~~~

### The cron_schedule format

The `cron_schedule` field has the following format:

    *    *    *    *    *    *
    ┬    ┬    ┬    ┬    ┬    ┬
    │    │    │    │    │    │
    │    │    │    │    │    └ Optional: Timezone, for example: 'America/New_York', 'UTC'
    │    │    │    │    └───── day_of_week (0-7) (0 or 7 is Sun, or use 3-letter names)
    │    │    │    └────────── month (1-12, or use 3-letter names)
    │    │    └─────────────── day_of_month (1-31, L, -1..-31)
    │    └──────────────────── hour (0-23)
    └───────────────────────── minute (0-59)

* When specifying day of week, both day 0 and day 7 are Sunday.
* Ranges and lists of numbers are allowed.
* Ranges or lists of names are not allowed.
* Ranges can include steps, so `1-9/2` is the same as `1,3,5,7,9`.
* Months and days of the week can be specified by name, using the first three letters (case does
  not matter).
* A `day_of_month` of `L` means the last day of the month.
* The timezone is recommended, to avoid issues with differing default timezones across servers and
  environments. For the complete list, see the
  [Wikipedia List of tz database time zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

#### cron_schedule examples

| Description                                                                                   | cron_schedule
|:----------------------------------------------------------------------------------------------|:-------------
| Every minute                                                                                  |`* * * * *`
| Every 10 minutes                                                                              |`*/10 * * * *`
| Every 30 minutes on the half hour                                                             |`0,30 * * * *`
| Every hour on the hour                                                                        |`0 * * * *`
| Every day at 2am                                                                              |`0 2 * * *`
| 5am and 5pm daily                                                                             |`0 5,17 * * *`
| Every 4 hours                                                                                 |`* */4 * * *`
| Every month                                                                                   |`0 0 1 * *`
| On the 5th and the 6th of every month                                                         |`0 0 5,6 * *`
| Last day of the month                                                                         |`0 12 L * *`
| 5 days before the end of the month                                                            |`0 0 -5 * *`
| Every January                                                                                 |`0 0 * Jan *`
| Every January, May and August                                                                 |`0 0 * Jan,May,Aug *`
| Quarterly                                                                                     |`0 0 1 */3 *`
| Annually                                                                                      |`0 0 1 1 *`
| Every Sunday and Friday at 5pm                                                                 |`0 17 * * Sun,Fri`
| First Monday of every month                                                                   |`0 12 * * Mon#1`
| Third Monday of every month                                                                   |`0 12 * * Mon#3`
| Last Sunday of every month                                                                    |`0 12 * * Sun#-1`
| Fri, Sat and Sun at 3:30pm                                                                     |`30 15 * * Fri,Sat,Sun`
| 4am and 5pm on Sunday and Monday only                                                          |`0 4,17 * * Sun,Mon`
| Every night from the 5th to the 12th                                                           |`30 0 5-12 * *`
| 10 days before the end of the month to 5 days before the end of the month                      |`0 0 -10--5 * *`
| Every second day, 10 days before the end of the month to 5 days before the end of the month    |`0 0 -10--2/2 * *`

To try out a cron entry and see when it would next run:

~~~ruby
Fugit::Cron.new("*/5 * * * *").next_time.to_utc_time
~~~

Or relative to a specific time:

~~~ruby
current_time = Time.parse("2018-01-01 10:00:00")
Fugit::Cron.new("*/5 * * * *").next_time(current_time).to_utc_time
~~~

### Running and changing a scheduled job

Make a scheduled job run immediately, rather than waiting for its next occurrence:

~~~ruby
MyCronJob.queued.first.run_now!
~~~

Change the schedule of an existing scheduled job:

~~~ruby
job               = MyCronJob.queued.first
job.cron_schedule = "* 1 * * * America/New_York"
job.save!
~~~

When the `cron_schedule` changes, the `run_at` is recalculated before saving, so the change takes
effect immediately.

### Scheduling options

The Cron plugin adds two further fields:

* `cron_singleton` (default `true`): prevent another instance of this job from being queued, running,
  failed, or paused with the _same_ `cron_schedule`. An instance with a different schedule string is
  still allowed.
* `cron_after_start` (default `true`): when `true`, the next instance is scheduled as soon as the
  current one starts, so a long-running instance does not delay the next occurrence. When `false`,
  the next instance is only scheduled once the current one completes, fails, or is aborted.

### Carrying field values across runs

When a scheduled job creates its next instance, custom field values are not carried over by default:

~~~ruby
class MyCronJob < RocketJob::Job
  include RocketJob::Plugins::Cron

  self.cron_schedule = "0 0 * * * UTC"

  field :name, type: String

  def perform
    # Called every night at midnight UTC
  end
end
~~~

~~~ruby
MyCronJob.create!(name: "Joe Bloggs")
~~~

The first run uses `name`, but the next scheduled instance loses it. Mark the field
`copy_on_restart: true` to carry the value forward:

~~~ruby
class MyCronJob < RocketJob::Job
  include RocketJob::Plugins::Cron

  self.cron_schedule = "0 0 * * * UTC"

  # Retain the field value between scheduled instances
  field :name, type: String, copy_on_restart: true

  def perform
    # Called every night at midnight UTC
  end
end
~~~

### Notes

* When a scheduled job's time arrives, it runs only if a worker is available. If workers are busy
  with higher priority jobs, it runs once those finish, or once their priority is lowered.
* A scheduled job is not rescheduled if it has passed its `expires_at`. This lets a scheduled job
  destroy itself at a future date by setting `expires_at`.
* When a scheduled job fails, it creates a new scheduled instance and clears the `cron_schedule` on
  the failed instance, so that retrying the failed instance does not create yet another schedule.

## Processing Window

A processing window ensures a job only runs between certain hours, regardless of when it was
created. This is useful for creating a job now that should only run later, during a specific window.
If the window is already open, the job can run immediately.

Examples:

* Process this job on Mondays between 8am and 10am.
* Run this job on the 1st of every month, from midnight, for the entire day.

Because the schedule supports timezones, it is easy to target UTC or any other zone.

~~~ruby
# Only run between 8:30am and 8:30pm Eastern. If it is after 8:30pm, schedule it
# to run at 8:30am the next day.
class BusinessHoursJob < RocketJob::Job
  include RocketJob::Plugins::ProcessingWindow

  # The start of the processing window
  self.processing_schedule = "30 8 * * * America/New_York"

  # How long the processing window stays open
  self.processing_duration = 12.hours

  def perform
    # Job will only run between 8:30am and 8:30pm Eastern
  end
end
~~~

**Note:** if a job is created during the window but, due to busy or unavailable workers, is not
processed before the window closes, it is re-queued for the beginning of the next window.

## Automatic Retry

To have a job automatically retry itself on failure, without any manual intervention, add the
`RocketJob::Plugins::Retry` plugin:

~~~ruby
class ReportJob < RocketJob::Job
  include RocketJob::Plugins::Retry

  def perform
    # Perform work here
  end
end
~~~

### Retry attempts

The default number of attempts before giving up is 25, which spans almost 25 days because of the
exponential back-off between retries. Change it with `retry_limit`:

~~~ruby
class ReportJob < RocketJob::Job
  include RocketJob::Plugins::Retry

  # Maximum number of times to retry before giving up
  self.retry_limit = 3

  def perform
    # Perform work here
  end
end
~~~

Override the limit per instance, or disable retries entirely for one instance with `retry_limit: 0`:

~~~ruby
ReportJob.create!(retry_limit: 10)
ReportJob.create!(retry_limit: 0)
~~~

### Notes

* Each retry is scheduled to run in the future using an exponential back-off, to avoid overwhelming
  a failed resource. While waiting to retry, the job appears as `queued` (or `running`), not
  `failed`, in [Mission Control](mission_control.html).
* A job is not retried if it has expired, if it exceeds its `retry_limit`, or if it fails
  validations when the retry is attempted (an error is logged and the job is not retried).
* When a job is retried, its previous exception is logged and the `exception` attribute is cleared.

## Singleton

The Singleton plugin ensures that only one instance of a job class is `running`, `queued`, or
`paused` at a time. Saving a new instance fails validation while another is active:

~~~ruby
class ReportJob < RocketJob::Job
  include RocketJob::Plugins::Singleton

  def perform
    # Perform work here
  end
end
~~~

## Throttling

Throttles limit how much work of a given kind runs at once, so jobs cannot overwhelm shared
resources.

### Throttle Running Jobs

Because it is common to run hundreds or thousands of workers, an unbounded job class could mount a
distributed denial of service against a shared resource. Limit how many instances of a job class run
at the same time with `throttle_running_jobs`:

~~~ruby
class MyJob < RocketJob::Job
  # Maximum number of jobs of this class to run at the same time
  self.throttle_running_jobs = 25

  def perform
    # ...
  end
end
~~~

Jobs in excess of the limit stay `queued` and only start once the running count drops below
`throttle_running_jobs`.

To throttle across several job classes together, set a shared `throttle_group` on each; the limit
then applies to the combined group rather than per class.

**Notes:**

* The number of running jobs will not exceed the limit.
* A job may briefly appear to run over the limit and then immediately return to `queued`. This is
  expected: a worker claims the job and only then verifies the throttle, which prevents another
  worker from grabbing the same job and exceeding the limit.

### Throttle Dependent Jobs

Prevent a job from running while instances of other job classes are running. This job stays queued
while any `FirstJob` or `SecondJob` is running:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Plugins::ThrottleDependentJobs

  self.dependent_jobs = ["FirstJob", "SecondJob"]

  def perform
    # ...
  end
end
~~~

The dependent job classes can also be declared with `depends_on_job`:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Plugins::ThrottleDependentJobs

  depends_on_job FirstJob, SecondJob

  def perform
    # ...
  end
end
~~~

### Custom Throttles

Define custom throttles with `define_throttle`. The named method returns true when the throttle is
exceeded, in which case the job is left queued and re-checked later (every
`RocketJob::Config.re_check_seconds`, which defaults to 60 seconds):

~~~ruby
class MyJob < RocketJob::Job
  # Do not run this job when the MySQL replica delay exceeds 5 minutes
  define_throttle :mysql_throttle_exceeded?

  def perform
    # ...
  end

  private

  # Returns true if the MySQL replica delay exceeds 5 minutes
  def mysql_throttle_exceeded?
    status        = ActiveRecord::Base.connection.select_one("show slave status")
    seconds_delay = Hash(status)["Seconds_Behind_Master"].to_i
    seconds_delay >= 300
  end
end
~~~

## Transactions

The `RocketJob::Plugins::Transaction` plugin wraps every `perform` call in an Active Record
transaction. If `perform` raises an exception, any database changes are rolled back. For
[batch jobs](batch.html), the transaction wraps each slice, so an entire slice either succeeds or is
rolled back.

~~~ruby
# Update a User and create an Audit entry as a single database transaction.
# If Audit.create! fails, the user change is also rolled back.
class MyJob < RocketJob::Job
  include RocketJob::Plugins::Transaction

  def perform
    u = User.find_by(name: "Jack")
    u.age = 21
    u.save!

    Audit.create!(table: "user", description: "Changed age to 21")
  end
end
~~~

**Performance:**

* On CRuby an empty transaction block takes about 1ms.
* On JRuby an empty transaction block takes about 55ms.

**Note:** this plugin is only activated if Active Record has already been loaded.

## Persistence

The persistence methods follow the conventions used by other ActiveRecord-like frameworks.

### Job.create!

Enqueue a single job for processing. Raises an exception on a validation error.

~~~ruby
ReportJob.create!(report_date: Date.yesterday)
~~~

### Job#save!

Enqueue a new job, or save changes to an existing one, atomically. Raises an exception on a
validation error.

~~~ruby
job             = ReportJob.new
job.report_date = Date.yesterday
job.save!
~~~

### Job#update_attributes!

Update the supplied attributes, along with any other dirty fields. Raises an exception on a
validation error.

~~~ruby
job.update_attributes!(report_date: Date.yesterday)
~~~

### Job#update_attribute

Update a single attribute, bypassing validations.

~~~ruby
job.update_attribute(:report_date, Date.yesterday)
~~~

### Job#delete

Delete the job from the database _without_ running callbacks.

~~~ruby
job.delete
~~~

### Job#destroy

Delete the job from the database, running callbacks.

~~~ruby
job.destroy
~~~

### Job.delete_all

Delete jobs from the database _without_ running callbacks. Scope it to a job class, or call it on
`RocketJob::Job` for all jobs.

~~~ruby
ReportJob.delete_all
RocketJob::Job.delete_all
~~~

### Job.destroy_all

Delete jobs from the database, running callbacks. Scope it to a job class, or call it on
`RocketJob::Job` for all jobs.

~~~ruby
ReportJob.destroy_all
RocketJob::Job.destroy_all
~~~

## Queries

Beyond [Mission Control](mission_control.html), it is often useful to access jobs programmatically
while they run. Because each job is a single MongoDB document, everything about a job is available
through ordinary queries.

Find the most recently submitted job:

~~~ruby
job = RocketJob::Job.last
~~~

Find a specific job by id:

~~~ruby
job = RocketJob::Job.find("55aeaf03a26ec0c1bd00008d")
~~~

Change its priority:

~~~ruby
job          = RocketJob::Job.find("55aeaf03a26ec0c1bd00008d")
job.priority = 32
job.save!
~~~

Or update an attribute directly, skipping the separate save:

~~~ruby
job = RocketJob::Job.find("55aeaf03a26ec0c1bd00008d")
job.update_attributes(priority: 32)
~~~

How long has the last job been running?

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
RocketJob::Job.failed.each(&:retry!)
~~~

Is a particular job still running?

~~~ruby
job = RocketJob::Job.find("55aeaf03a26ec0c1bd00008d")

if job.completed?
  puts "Finished!"
elsif job.running?
  puts "The job is being processed by worker: #{job.worker_name}"
end
~~~

The state scopes (`queued`, `running`, `completed`, `failed`, `paused`, `aborted`) and the
`scheduled` and `queued_now` scopes are all available. For full query syntax, see the
[Mongoid Queries documentation](https://www.mongodb.com/docs/mongoid/current/reference/queries/).

### Querying custom fields

Custom fields can be used in queries to find a specific instance of a job class:

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

## Callbacks

Callbacks let custom behavior run at many points in the job lifecycle.

Perform callbacks:

* `before_perform`
* `after_perform`
* `around_perform`

Persistence callbacks:

* `after_initialize`
* `before_validation`
* `after_validation`
* `before_save`
* `before_create`
* `after_create`
* `after_save`

Lifecycle (state transition) callbacks, one pair per [state transition](#the-job-lifecycle):

* `before_start` / `after_start`
* `before_complete` / `after_complete`
* `before_fail` / `after_fail`
* `before_retry` / `after_retry`
* `before_pause` / `after_pause`
* `before_resume` / `after_resume`
* `before_abort` / `after_abort`

Send an email when a job starts, completes, fails, or aborts:

~~~ruby
class MyJob < RocketJob::Job
  field :email_recipients, type: Array

  after_start    :email_started
  after_complete :email_completed
  after_fail     :email_failed
  after_abort    :email_aborted

  def perform
    # ...
  end

  private

  def email_started
    MyJob.started(email_recipients, self).deliver
  end

  def email_completed
    MyJob.completed(email_recipients, self).deliver
  end

  def email_failed
    MyJob.failed(email_recipients, self).deliver
  end

  def email_aborted
    MyJob.aborted(email_recipients, self).deliver
  end
end
~~~

Callbacks can be used to insert "middleware" into a single job class, or into all jobs. For example,
an `after_fail` callback can implement a custom retry policy, such as retrying immediately up to
three times.

Before callbacks run in the order they are defined. After callbacks run in the _reverse_ order to
which they were defined:

~~~
before_1
before_2
perform
after_2
after_1
~~~

A full example, including around callbacks:

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

Run it inline, without workers:

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

For more on callbacks, see the
[Mongoid Callbacks documentation](https://www.mongodb.com/docs/mongoid/current/reference/callbacks/).

## Validations

The usual [Active Model validations](https://guides.rubyonrails.org/active_record_validations.html)
are available, since jobs expose Active Model:

~~~ruby
class ReportJob < RocketJob::Job
  field :login, type: String
  field :count, type: Integer

  validates_presence_of :login
  validates :count, inclusion: 1..100
end
~~~

Validations run before a job is saved and before `perform_now` runs the job inline, so a malformed
job is rejected up front rather than mid-run.

## Exception Handling

When a job fails, the exception and its full backtrace are stored on the job to aid problem
determination:

~~~ruby
if job.reload.failed?
  puts "Job failed with: #{job.exception.klass}: #{job.exception.message}"
  puts "Backtrace:"
  puts job.exception.backtrace.join("\n")
end
~~~

## Thread Safety

Each Rocket Job server process runs a pool of worker threads, one job per thread, all in the same
process. Many jobs therefore run `perform` concurrently, so a job's `perform` method must be
thread-safe. See [Architecture and Internals](architecture.html) for why Rocket Job uses threads.

Each job runs on its own instance, so ordinary instance state inside `perform` (the job's own
fields and instance variables) is safe. What is not safe is shared mutable state:

* Do not write to global variables or mutable class-level state from `perform`. Two threads can
  touch them at once.
* Make any shared cache thread-safe. A lazy `@@cache ||= ...` on shared class state can race;
  initialize it at load time, or use a thread-safe structure such as `Concurrent::Map` from
  `concurrent-ruby`, which Rocket Job already depends on.
* Any third party client called inside `perform` must itself be thread-safe, or be created per call.

~~~ruby
class ReportJob < RocketJob::Job
  def perform
    # Safe: local and instance state, scoped to this job instance / thread
    rows = Report.rows_for(report_date)
    self.row_count = rows.size
  end
end
~~~

## Extending Jobs with Plugins

`RocketJob::Job` is composed from plugin modules (see
[the composition model](architecture.html#the-job-is-a-composition-of-plugins)). Custom behavior can be
packaged the same way, as an `ActiveSupport::Concern` that adds fields, callbacks, validations, and
methods to any job that includes it.

For example, a reusable plugin that emails a list of recipients whenever a job fails:

~~~ruby
require "active_support/concern"

module EmailOnFailure
  extend ActiveSupport::Concern

  included do
    # Add a persisted, user-editable field to every job that includes this plugin
    field :email_recipients, type: Array, default: []

    # Hook into the job lifecycle
    after_fail :email_failure
  end

  private

  def email_failure
    return if email_recipients.empty?

    JobMailer.failed(email_recipients, self).deliver_now
  end
end
~~~

Include it in any job:

~~~ruby
class ReportJob < RocketJob::Job
  include EmailOnFailure

  def perform
    # ...
  end
end
~~~

~~~ruby
ReportJob.create!(email_recipients: ["ops@example.com"])
~~~

Before writing a plugin, check whether a built-in one already covers the need. Rocket Job ships
optional plugins under `RocketJob::Plugins` ([Cron](#scheduled-jobs), [Singleton](#singleton),
[Retry](#automatic-retry), [ProcessingWindow](#processing-window),
[ThrottleDependentJobs](#throttle-dependent-jobs), [Transaction](#transactions)) and batch plugins
under `RocketJob::Batch`. For example, include `RocketJob::Plugins::Singleton` rather than
hand-rolling a singleton validation.

## Logging

Every job has a `logger`, provided by [Semantic Logger](https://logger.rocketjob.io), with the job's
class name and id already tagged onto each entry:

~~~ruby
class ReportJob < RocketJob::Job
  def perform
    logger.info "Starting report"
    logger.measure_info("Built report") do
      # ... work whose duration is logged ...
    end
  end
end
~~~

Rocket Job automatically logs the start and completion of every `perform`, including its duration,
which is also emitted as a metric for systems such as statsd.

The `log_level` field overrides the log level for a single job, which is useful for quietening a
noisy job or, conversely, turning up logging to `:trace` to debug one job:

~~~ruby
# Only log warnings and above for this job instance
ReportJob.create!(log_level: :warn)
~~~

For full logging configuration, see the [Semantic Logger documentation](https://logger.rocketjob.io).

## Writing Tests

### In-memory jobs

Jobs can be created and run entirely in memory, without being persisted. This is useful for tests,
for trying out jobs in a console, and even, in production, for running a diagnostic job in a console
without active workers picking it up.

~~~ruby
class ReportJob < RocketJob::Job
  # Retain the job on completion
  self.destroy_on_complete = false

  def perform
    puts "Hello World"
    45
  end
end
~~~

Create an in-memory instance with `.new` instead of `.create!`:

~~~ruby
job = ReportJob.new
~~~

Run the whole job in memory with `#perform_now`. For a simple job, it returns the value that
`perform` returned:

~~~ruby
job.perform_now
# => 45
~~~

The job should complete successfully:

~~~ruby
job.completed?
# => true
~~~

If it failed in memory, inspect its attributes:

~~~ruby
p(job.attributes) if job.failed?
~~~

### Minitest example

A Minitest test for the `ReportJob` above:

~~~ruby
require_relative "test_helper"

class ReportJobTest < Minitest::Test
  describe ReportJob do
    # Create an in-memory instance of the ReportJob
    let(:report_job) { ReportJob.new }

    describe "#perform_now" do
      it "returns 45" do
        # A new job is immediately in queued state
        assert report_job.queued?

        # perform_now returns the value that perform returned
        assert_equal 45, report_job.perform_now

        # The job should complete successfully
        assert report_job.completed?, -> { report_job.attributes }
      end
    end
  end
end
~~~

## Command Line Interface

Rocket Job ships with the `rocketjob` command for starting and managing servers.

### Starting a server

Start a server with the default of 10 workers:

~~~bash
bundle exec rocketjob
~~~

Start a server with 2 workers:

~~~bash
bundle exec rocketjob --workers 2
~~~

### Limiting which jobs a server runs

A server can be restricted to a subset of job classes, or to jobs matching a query. This is useful
for dedicating servers to particular workloads.

Run only `DirmonJob` and `WeeklyReportJob` (the filter is a case-insensitive regular expression):

~~~bash
bundle exec rocketjob --include "DirmonJob|WeeklyReportJob"
~~~

Run everything _except_ those classes:

~~~bash
bundle exec rocketjob --exclude "DirmonJob|WeeklyReportJob"
~~~

Restrict to jobs matching a MongoDB query, supplied as JSON. For example, only high priority jobs:

~~~bash
bundle exec rocketjob --where '{"priority":{"$lte":25}}'
~~~

**Note:** regular expressions and JSON must be quoted and escaped appropriately for the shell.

### Server options

| Option                          | Description
|:--------------------------------|:------------
| `-n`, `--name NAME`             | Unique name of this server. Default: `host_name:PID`.
| `-w`, `--workers COUNT`         | Number of worker threads to start.
| `--include REGEXP`              | Only run job classes matching this case-insensitive regular expression.
| `-E`, `--exclude REGEXP`        | Do not run job classes matching this case-insensitive regular expression.
| `-W`, `--where JSON`            | Only run jobs matching this MongoDB query filter, as a JSON string.
| `-q`, `--quiet`                 | Write only to the log file, not stdout. Needed when running as a daemon.
| `-d`, `--dir DIR`               | Directory of the Rails app, if not the current directory.
| `-e`, `--environment ENV`       | Environment to run in. Default: `RAILS_ENV` or `RACK_ENV` or `development`.
| `-l`, `--log_level LEVEL`       | Log level: `trace`, `debug`, `info`, `warn`, `error`, or `fatal`.
| `-f`, `--log_file FILE`         | Log file to write to. Default: `log/<environment>.log`.
| `--pidfile PATH`                | Write a pidfile to PATH.
| `-m`, `--mongo FILE`            | Mongoid config file. Default: `config/mongoid.yml`.
| `-s`, `--symmetric-encryption FILE` | Symmetric Encryption config file. Default: `config/symmetric-encryption.yml`.
| `-v`, `--version`               | Print the Rocket Job version.

### Managing running servers

These commands send an event to running servers, coordinated through MongoDB. Each takes an optional
complete or partial server name; with no name, the action applies to all servers.

| Option                    | Description
|:--------------------------|:------------
| `--list [FILTER]`         | List active servers, optionally filtered by name.
| `--refresh [SECONDS]`     | When listing, refresh every SECONDS (default 1 second).
| `--stop [SERVER_NAME]`    | Stop server(s) once their in-process workers have finished.
| `--kill [SERVER_NAME]`    | Hard kill server(s).
| `--pause [SERVER_NAME]`   | Pause server(s).
| `--resume [SERVER_NAME]`  | Resume paused server(s).
| `--dump [SERVER_NAME]`    | Have server(s) write a worker thread dump to their log file.

## Next steps

* [Batch Guide](batch.html): process large files in parallel across many workers.
* [Dirmon](dirmon.html): trigger jobs automatically when files arrive.
* [Mission Control](mission_control.html): the web interface.
* [Installation](installation.html): Rails, standalone, and the web interface.

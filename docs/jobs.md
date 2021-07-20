---
layout: default
---

# Included Jobs

#### Table of Contents

* [Housekeeping Job](#housekeeping-job)
* [Dirmon Job](#dirmon-job)
* [OnDemandJob](#ondemandjob)
* [OnDemandBatchJob](#ondemandbatchjob)

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
  data["result"] = data['a'] * data['b']
CODE

RocketJob::Jobs::OnDemandJob.create!(
  code:           code,
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

---
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

By default output is not collected, call `#collect_output` to collect output.

Example:

~~~ruby
job = RocketJob::Jobs::OnDemandBatchJob(description: 'Fix data', code: code, throttle_running_workers: 5, priority: 30)
job.collect_output
job.save!
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



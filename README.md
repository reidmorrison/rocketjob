# rocket_job

High volume, priority based, batch processing solution for Ruby.

## Status

Alpha - Feedback on the API is welcome. API will change.

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
code to collect it's output. RocketJob has built in support to collect the results
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

`RocketJob` was created out of necessity due to constant support. End-users were
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

Since `RocketJob` uploads the entire file, or all data for processing it does not
require jobs to store the data in other databases.
Additionally, `RocketJob` supports encryption and compression of any data uploaded
into Sliced Jobs to ensure PCI compliance and to prevent sensitive from being exposed
either at rest in the data store, or in flight as it is being read or written to the
backend data store.
Often large files received for processing contain sensitive data that must not be exposed
in the backend job store. Having this capability built-in ensures all our jobs
are properly securing sensitive data.

Since moving to `RocketJob` our production support has diminished and now we can
focus on writing code again. :)

## Management

The companion project [RocketJob Mission Control](https://github.com/mjcloutier/rocket_job_mission_control)
contains the Rails Engine that can be loaded into your Rails project to add
a web interface for viewing and managing `RocketJob` jobs.

`RocketJob Mission Control` can also be run stand-alone in a shell Rails application.

By separating `RocketJob Mission Control` into a separate gem means it does not
have to be loaded where `RocketJob` jobs are defined or run.

## Jobs

Simple single task jobs:

Example job to run in a separate worker process

```ruby
class MyJob
  include RocketJob::Worker

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

## Sliced jobs

Sliced jobs consist of more than one record that needs to be processed.

```ruby
class MyJob
  include RocketJob::Worker

  rocket_job(RocketJob::SlicedJob) do |job|
    job.destroy_on_complete = false
    job.encrypt             = true
    job.compress            = true
    job.description         = "Reverse names"
    job.slice_size          = 100
    job.collect_output      = true
    job.priority            = 25
  end

  # Method to call asynchronously by the worker
  def perform(name)
    name.reverse
  end
end
```

Upload a file for processing, for example `names.csv` which could contain:

```
jack
jane
bill
john
blake
chris
dave
marc
```

To queue the above job for processing:

```ruby
job = MyJob.perform_later do |job|
  job.upload('names.csv')
end
```

Once the job has completed, download the results into a file:

```ruby
job.download('names_reversed.csv')
```

To improve performance and throughput, records are grouped together into slices.
Benefits of processing records in slices:
* Each slice is processed by a single worker at a time.
* One read fetches all the records in that slice.
* The results are written as a single slice to the results collection.
* Less IO wait time.
* Less load on the system.

Some factors for deciding on the slice size for the records:
* How many records can a worker process in 1 to 5 minutes?

If the slice size is too high workers will be busy too long on a single slice
that will hamper worker restarts, for example during deployments.

If the slice size is too small the workers will hammer the system CPU and network IO
reading slices with very little time actually spent on performing the
required work for each record.

Loaded records are kept in a separate collection for better performance, and
once each slice of records is processed it is deleted. When the job is completed
the entire collection that held the records is dropped.

Optionally, the result from processing each record can be stored by `RocketJob`.
When `collect_results` is `true`, the results returned from the workers are
held in a separate collection for that instance of the job.
When the job is destroyed its upload and download collections are automatically
dropped to ensure housekeeping.

Loaded records are kept in a separate collection for better performance, and
once each slice of records is processed it is deleted. When the job is completed
the entire collection that held the records is dropped.

## Configuration

MongoMapper will already configure itself in Rails environments. Sometimes we want
to use a different Mongo Database instance for the records and results.

For example, the RocketJob::Job can be stored in a Mongo Database that is replicated
across data centers, whereas we may not want to replicate record and result data
due to it's sheer volume.

```ruby
config.before_initialize do
  # If this environment has a separate Work server
  # Share the common mongo configuration file
  config_file = root.join('config', 'mongo.yml')
  if config_file.file?
    if config = YAML.load(ERB.new(config_file.read).result)["#{Rails.env}_work]
      options = (config['options']||{}).symbolize_keys
      # In the development environment the Mongo driver generates a lot of
      # network trace log data, move its debug logging to :trace
      options[:logger] = SemanticLogger::DebugAsTraceLogger.new('Mongo:Work')
      RocketJob::Config.mongo_work_connection = Mongo::MongoClient.from_uri(config['uri'], options)

      # It is also possible to store the jobs themselves in a separate MongoDB database
      # RocketJob::Config.mongo_connection = Mongo::MongoClient.from_uri(config['uri'], options)
    end
  else
    puts "\nmongo.yml config file not found: #{config_file}"
  end
end
```

## Requirements

MongoDB V2.6 or greater

* V2.6 includes a feature to allow lookups using the `$or` clause to use an index

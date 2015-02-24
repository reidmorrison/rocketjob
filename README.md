batch_job
=========

High volume, priority based, Enterprise Batch Processing solution for Ruby

status
======

Early Development, not ready for use

## Multi-record jobs

MultiRecordJob job is a job that consists of more than one record that needs
to be processed.

To improve performance and throughput, records are grouped together into blocks.
Benefits of processing records in blocks:
* Each block is processed by a single worker at a time.
* One read fetches all the records in that block.
* The results are written as a single block to the results collection.
* Less IO wait time.
* Less load on the system.

Some factors for deciding on the block size for the records:
* How many records can a worker process in 1 to 5 minutes?

If the block size is too high workers will be busy too long on a single block
that will block restarts during for example deploys.

If the block size is too small the workers will hammer the system CPU and network IO
reading blocks with very little time actually spent on performing the
required work for each record.

Loaded records are kept in a separate collection for better performance, and
once each block of records is processed it is deleted. When the job is completed
the entire collection that held the records is dropped.

Optionally, the result from processing each record can be stored by Batch Job.
When `collect_results` is `true`, the results returned from the workers are
held in a separate collection for that instance of the job.
When the job is destroyed

Loaded records are kept in a separate collection for better performance, and
once each block of records is processed it is deleted. When the job is completed
the entire collection that held the records is dropped.

## Configuration

MongoMapper will already configure itself in Rails environments. Sometimes we want
to use a different Mongo Database instance for the records and results.

For example, the Batch::Job can be stored in a Mongo Database that is replicated
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
      options[:logger] = SemanticLogger::DebugAsTraceLogger.new('Mongo:Work')
      BatchJob::MultiRecordJob.work_connection = Mongo::MongoClient.from_uri(config['uri'], options)
    end
  else
    puts "\nmongo.yml config file not found: #{config_file}"
  end
end
```

## Requirements

Mongo V2.6 or greater

* V2.6 includes a feature to allow lookups using the `$or` clause to use an index

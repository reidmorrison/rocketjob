batch_job
=========

High volume, priority based, Enterprise Batch Processing solution for Ruby

status
======

Early Development, not ready for use

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
      options[:logger] = SemanticLogger['MongoWork']
      BatchJob::MultiRecordJob.work_connection = Mongo::MongoClient.from_uri(config['uri'], options)
    end
  else
    puts "\nmongo.yml config file not found: #{config_file}"
  end
end
```
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require 'minitest/autorun'
require 'minitest/reporters'
require 'minitest/stub_any_instance'
require 'shoulda/context'
require 'batch_job'
require 'yaml'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

# Setup MongoMapper from mongo config file
config_file = File.join(File.dirname(__FILE__), 'config', 'mongo.yml')
if config = YAML.load(ERB.new(File.read(config_file)).result)
  cfg                    = config['test']
  options                = cfg['options'] || {}
  options[:logger]       = SemanticLogger['Mongo']

  MongoMapper.config     = cfg
  MongoMapper.connection = Mongo::MongoClient.from_uri(cfg['uri'], options)
  MongoMapper.database   = MongoMapper.connection.db.name

  # If this environment has a separate Work server
  if cfg = config['test_work']
    options                = cfg['options'] || {}
    options[:logger]       = SemanticLogger['MongoWork']
    BatchJob::MultiRecordJob.work_connection = Mongo::MongoClient.from_uri(cfg['uri'], options)
  end
end

# Ensure Batch Job Indexes have been created
BatchJob::Job.create_indexes



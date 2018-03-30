$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'
ENV['TZ'] = 'America/New_York'

require 'yaml'
require 'minitest/autorun'
require 'minitest/stub_any_instance'
require 'awesome_print'
require 'rocketjob'

SemanticLogger.add_appender(file_name: 'test.log', formatter: :color)
SemanticLogger.default_level = :debug

RocketJob::Config.load!('test', 'test/config/mongoid.yml')
Mongoid.logger       = SemanticLogger[Mongoid]
Mongo::Logger.logger = SemanticLogger[Mongo]

# RocketJob::Job.collection.database.command(dropDatabase: 1)

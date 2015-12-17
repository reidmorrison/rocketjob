$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require 'yaml'
require 'minitest/autorun'
require 'minitest/reporters'
require 'minitest/stub_any_instance'
require 'awesome_print'
require 'rocketjob'

MiniTest::Reporters.use! MiniTest::Reporters::SpecReporter.new

SemanticLogger.add_appender('test.log', &SemanticLogger::Appender::Base.colorized_formatter)
SemanticLogger.default_level = :debug

RocketJob::Config.load!('test', 'test/config/mongo.yml')

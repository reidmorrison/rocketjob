$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

begin
  require 'active_model/serializers'
rescue LoadError
  # Only used when running Rails 5
end
require 'yaml'
require 'minitest/autorun'
require 'minitest/reporters'
require 'minitest/stub_any_instance'
require 'awesome_print'
require 'rocketjob'

MiniTest::Reporters.use! MiniTest::Reporters::SpecReporter.new

SemanticLogger.add_appender(file_name: 'test.log', formatter: :color)
SemanticLogger.default_level = :debug

RocketJob::Config.load!('test', 'test/config/mongo.yml')

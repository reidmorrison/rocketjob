$LOAD_PATH.unshift File.dirname(__FILE__) + "/../lib"
ENV["TZ"] = "America/New_York"

require "yaml"
require "minitest/autorun"
require "minitest/stub_any_instance"
require "minitest/reporters"
require "amazing_print"
require "rocketjob"

SemanticLogger.add_appender(file_name: "test.log", formatter: :color)
SemanticLogger.default_level = :info

RocketJob::Config.load!("test", "test/config/mongoid.yml", "test/config/symmetric-encryption.yml")
Mongoid.logger       = SemanticLogger[Mongoid]
Mongo::Logger.logger = SemanticLogger[Mongo]

# Cleanup test collections
RocketJob::Job.collection.database.collections.each do |collection|
  collection.drop
end

reporters = [
  Minitest::Reporters::ProgressReporter.new,
  SemanticLogger::Reporters::Minitest.new
]
Minitest::Reporters.use!(reporters)

# Weed out usages of the BSON Symbol type
class Symbol
  def bson_type
    raise(Mongo::Error::OperationFailure, "Unsupported BSON Symbol: :#{to_s}")
  end
end

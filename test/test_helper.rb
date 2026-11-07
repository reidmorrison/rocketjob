$LOAD_PATH.unshift File.dirname(__FILE__) + "/../lib"
ENV["TZ"] = "America/New_York"

# Start SimpleCov before any application code is loaded so coverage is tracked.
require "simplecov"
SimpleCov.start do
  add_filter "/test/"
end

require "yaml"
require "minitest/autorun"
require "minitest/mock"
require "minitest/stub_any_instance"
require "minitest/reporters"
require "amazing_print"
require "rocketjob"

SemanticLogger.add_appender(file_name: "test.log", formatter: :color)
SemanticLogger.default_level = :info

RocketJob::Config.load!("test", "test/config/mongoid.yml", "test/config/symmetric-encryption.yml")
Mongoid.logger       = SemanticLogger[Mongoid]
Mongo::Logger.logger = SemanticLogger[Mongo]

# The MongoDB database that the tests use, which test/config/mongoid.yml names for each git worktree.
TEST_DATABASE = Mongoid::Clients.default.database.name

# Cleanup test collections
RocketJob::Job.collection.database.collections.each(&:drop)

reporters = [
  Minitest::Reporters::DefaultReporter.new,
  SemanticLogger::Reporters::Minitest.new
]
Minitest::Reporters.use!(reporters)

# Weed out usages of the BSON Symbol type
class Symbol
  def bson_type
    raise(Mongo::Error::OperationFailure, "Unsupported BSON Symbol: :#{self}")
  end
end

# Collects the deprecation warnings that Rocket Job reports, see RocketJob::Deprecation, for a test that includes it.
module DeprecationWarnings
  # Returns [Array<String>] the deprecation warnings that Rocket Job reported while the block runs, with deprecation
  # warnings on, or off when `enabled` is false.
  def deprecation_warnings(enabled: true, &)
    warnings = []
    previous = Warning[:deprecated]
    Warning[:deprecated] = enabled
    collect = lambda do |message, category: nil|
      warnings << message if category == :deprecated && message.include?("Rocket Job: ")
    end
    Warning.stub(:warn, collect, &)
    warnings
  ensure
    Warning[:deprecated] = previous
  end
end

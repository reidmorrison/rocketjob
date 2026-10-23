$LOAD_PATH.unshift File.dirname(__FILE__) + "/../lib"
ENV["TZ"] = "America/New_York"

# Start SimpleCov before any application code is loaded so coverage is tracked.
require "simplecov"
SimpleCov.start do
  add_filter "/test/"
end

require "yaml"
require "digest"
require "minitest/autorun"
require "minitest/mock"
require "minitest/stub_any_instance"
require "minitest/reporters"
require "amazing_print"
require "rocketjob"

SemanticLogger.add_appender(file_name: "test.log", formatter: :color)
SemanticLogger.default_level = :info

# The MongoDB database that the tests use, see test/config/mongoid.yml. The tests drop its collections when they
# start, so each git worktree, whose .git is a file rather than a directory, gets a database of its own, named after
# its directory, so that the tests of worktrees that run at the same time do not drop each other's collections. The
# main checkout, and CI, use rocketjob_test. Set ROCKETJOB_TEST_DATABASE to choose another.
TEST_DATABASE = ENV["ROCKETJOB_TEST_DATABASE"] ||= begin
  root = File.expand_path("..", __dir__)
  if File.file?(File.join(root, ".git"))
    "rocketjob_test_#{File.basename(root).gsub(/[^A-Za-z0-9_-]/, '_')[0, 30]}_#{Digest::SHA256.hexdigest(root)[0, 6]}"
  else
    "rocketjob_test"
  end
end

RocketJob::Config.load!("test", "test/config/mongoid.yml", "test/config/symmetric-encryption.yml")
Mongoid.logger       = SemanticLogger[Mongoid]
Mongo::Logger.logger = SemanticLogger[Mongo]

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

$LOAD_PATH.unshift File.dirname(__FILE__) + "/../lib"
ENV["TZ"] = "America/New_York"

# Start SimpleCov before any application code is loaded so coverage is tracked.
require "simplecov"
SimpleCov.start do
  skip "/test/"
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

# Stubs Time.now in a test, rather than Minitest's #stub, which undefines its stub before it restores the original, so
# that another thread, such as one of the Mongo driver, which JRuby runs at the same time, can find Time.now undefined
# in between, and raise NoMethodError.
module StubTimeNow
  # Yields with Time.now returning the supplied time, for every thread, as `Time.stub(:now, time)` does.
  #
  # Returns the result of the block.
  def stub_time_now(time)
    original = Time.singleton_class.instance_method(:now)
    Time.singleton_class.define_method(:now) { |*_args, **_kwargs| time }
    yield
  ensure
    Time.singleton_class.define_method(:now, original)
  end
end
Minitest::Test.include(StubTimeNow)

# Weed out usages of the BSON Symbol type
class Symbol
  def bson_type
    raise(Mongo::Error::OperationFailure, "Unsupported BSON Symbol: :#{self}")
  end
end

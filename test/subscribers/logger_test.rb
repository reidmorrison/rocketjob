require_relative "../test_helper"

class LoggingTest < ActiveSupport::TestCase
  describe RocketJob::Subscribers::Logger do
    before do
      RocketJob::Supervisor.logger.level = :debug
    end

    after do
      RocketJob::Supervisor.logger.level = nil
    end

    it "Changes specific log level from debug to trace" do
      RocketJob::Subscribers::Logger.new.set(class_name: "RocketJob::Supervisor", level: :trace)
      assert_equal :trace, RocketJob::Supervisor.logger.level
    end

    it "Changes global log level from debug to trace" do
      before = SemanticLogger.default_level
      RocketJob::Subscribers::Logger.new.set(level: :trace)
      assert_equal :trace, SemanticLogger.default_level
      SemanticLogger.default_level = before
    end

    it "Changes specific log level from debug to trace" do
      RocketJob::Subscribers::Logger.new.set(class_name: "RocketJob::Supervisor", level: :trace)
      assert_equal :trace, RocketJob::Supervisor.logger.level
    end

    it "Filters based on host_name" do
      host = RocketJob::Subscribers::Logger.host_name
      RocketJob::Subscribers::Logger.new.set(class_name: "RocketJob::Supervisor", level: :trace, host_name: host)
      assert_equal :trace, RocketJob::Supervisor.logger.level
    end

    it "Skips different host_name" do
      host = "someone-else"
      RocketJob::Subscribers::Logger.new.set(class_name: "RocketJob::Supervisor", level: :trace, host_name: host)
      assert_equal :debug, RocketJob::Supervisor.logger.level
    end

    it "Filters based on pid" do
      process_id = $$
      RocketJob::Subscribers::Logger.new.set(class_name: "RocketJob::Supervisor", level: :trace, pid: process_id)
      assert_equal :trace, RocketJob::Supervisor.logger.level
    end

    it "Skips a different pid" do
      process_id = 8_888_888
      RocketJob::Subscribers::Logger.new.set(class_name: "RocketJob::Supervisor", level: :trace, pid: process_id)
      assert_equal :debug, RocketJob::Supervisor.logger.level
    end
  end
end

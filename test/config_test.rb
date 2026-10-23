require_relative "test_helper"

class ConfigTest < Minitest::Test
  describe RocketJob::Config do
    describe ".config" do
      it "support multiple databases" do
        assert_equal TEST_DATABASE, RocketJob::Job.collection.database.name
      end
    end
  end
end

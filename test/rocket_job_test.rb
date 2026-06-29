require_relative "test_helper"

class RocketJobTest < Minitest::Test
  describe RocketJob do
    describe ".seconds_as_duration" do
      it "returns nil when seconds is nil" do
        assert_nil RocketJob.seconds_as_duration(nil)
      end

      it "formats sub-millisecond durations with three decimals" do
        assert_equal "5.000ms", RocketJob.seconds_as_duration(0.005)
      end

      it "formats larger millisecond durations with one decimal" do
        assert_equal "50.0ms", RocketJob.seconds_as_duration(0.05)
      end

      it "formats durations of at least one second" do
        assert_equal "5.000s", RocketJob.seconds_as_duration(5.0)
      end

      it "formats durations of at least one minute" do
        assert_equal "1m 30s", RocketJob.seconds_as_duration(90.0)
      end

      it "formats durations of at least one hour" do
        assert_equal "1h 1m", RocketJob.seconds_as_duration(3661.0)
      end

      it "formats durations of at least one day" do
        # 1 day + 1 hour + 1 minute + 1 second
        assert_equal "1d 1h 1m", RocketJob.seconds_as_duration(90_061.0)
      end
    end

    describe "process flags" do
      before do
        @server = RocketJob.instance_variable_get(:@server)
        @rails  = RocketJob.instance_variable_get(:@rails)
      end

      after do
        RocketJob.instance_variable_set(:@server, @server)
        RocketJob.instance_variable_set(:@rails, @rails)
      end

      it "tracks the server flag" do
        RocketJob.instance_variable_set(:@server, false)
        refute RocketJob.server?
        RocketJob.server!
        assert RocketJob.server?
      end

      it "tracks the rails flag and standalone is its inverse" do
        RocketJob.instance_variable_set(:@rails, false)
        refute RocketJob.rails?
        assert RocketJob.standalone?

        RocketJob.rails!
        assert RocketJob.rails?
        refute RocketJob.standalone?
      end
    end
  end
end

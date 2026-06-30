require_relative "test_helper"

# Test subscriber that records the actions it receives so the dispatch
# logic in RocketJob::Subscriber can be verified.
class SubscriberTestSubscriber
  include RocketJob::Subscriber

  attr_reader :received

  def hello
    @received = [:hello]
  end

  def show(message:)
    @received = [:show, message]
  end

  def show_default(message: "Hello World")
    @received = [:show_default, message]
  end

  def boom(message:)
    raise "boom #{message}"
  end
end

# Subscriber that listens to every event published.
class SubscriberTestAllEvents
  include RocketJob::Subscriber

  self.event_name = RocketJob::Event::ALL_EVENTS

  def hello
    @received = true
  end
end

class SubscriberTest < Minitest::Test
  describe RocketJob::Subscriber do
    let(:subscriber) { SubscriberTestSubscriber.new }

    describe ".event_name" do
      it "defaults to the class name" do
        assert_equal "SubscriberTestSubscriber", SubscriberTestSubscriber.event_name
      end

      it "can be overridden to listen to all events" do
        assert_equal RocketJob::Event::ALL_EVENTS, SubscriberTestAllEvents.event_name
      end
    end

    describe ".test_mode!" do
      after do
        RocketJob::Subscriber.instance_variable_set(:@test_mode, false)
      end

      it "toggles test mode" do
        refute_predicate RocketJob::Subscriber, :test_mode?
        RocketJob::Subscriber.test_mode!

        assert_predicate RocketJob::Subscriber, :test_mode?
      end
    end

    describe ".publish" do
      it "raises ArgumentError for an unknown action" do
        error = assert_raises(ArgumentError) do
          SubscriberTestSubscriber.publish(:unknown_action)
        end
        assert_includes error.message, "unknown_action"
      end

      it "raises NotImplementedError when publishing to an all events subscriber" do
        assert_raises(NotImplementedError) do
          SubscriberTestAllEvents.publish(:hello)
        end
      end

      it "dispatches directly to subscribers in test mode" do
        RocketJob::Subscriber.test_mode!
        begin
          SubscriberTestSubscriber.subscribe do |instance|
            SubscriberTestSubscriber.publish(:show, message: "from publish")

            assert_equal [:show, "from publish"], instance.received
          end
        ensure
          RocketJob::Subscriber.instance_variable_set(:@test_mode, false)
        end
      end
    end

    describe ".subscribe" do
      it "registers the subscriber and returns a handle" do
        handle = SubscriberTestSubscriber.subscribe

        assert_kind_of Integer, handle
        RocketJob::Event.unsubscribe(handle)
      end

      it "yields the subscriber instance and unsubscribes afterwards" do
        yielded = nil
        SubscriberTestSubscriber.subscribe do |instance|
          yielded = instance

          assert_kind_of SubscriberTestSubscriber, instance
        end
        refute_nil yielded
      end
    end

    describe "#process_action" do
      it "calls a zero argument action" do
        subscriber.process_action(:hello, nil)

        assert_equal [:hello], subscriber.received
      end

      it "calls an action with keyword arguments, symbolizing string keys" do
        subscriber.process_action(:show, "message" => "hi there")

        assert_equal [:show, "hi there"], subscriber.received
      end

      it "uses default arguments when no parameters are supplied" do
        subscriber.process_action(:show_default, nil)

        assert_equal [:show_default, "Hello World"], subscriber.received
      end

      it "ignores an unknown action without raising" do
        assert_nil subscriber.process_action(:does_not_exist, nil)
        assert_nil subscriber.received
      end

      it "rescues ArgumentError when required arguments are missing" do
        # Missing the required :message keyword argument.
        subscriber.process_action(:show, {})

        assert_nil subscriber.received
      end

      it "rescues StandardError raised inside the action" do
        subscriber.process_action(:boom, "message" => "kaboom")

        assert_nil subscriber.received
      end
    end

    describe "#process_event" do
      it "raises NotImplementedError by default" do
        assert_raises(NotImplementedError) do
          subscriber.process_event("name", :action, {})
        end
      end
    end
  end
end

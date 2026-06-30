require_relative "test_helper"

# Subscriber that records the actions dispatched to it for a single named event.
class EventTestRecorder
  include RocketJob::Subscriber

  self.event_name = "EventTestRecorder"

  attr_reader :received

  def hello(message: nil)
    @received = [:hello, message]
  end

  def boom
    raise "boom"
  end
end

# Subscriber that listens to every published event.
class EventTestAllEvents
  include RocketJob::Subscriber

  self.event_name = RocketJob::Event::ALL_EVENTS

  attr_reader :events

  def initialize
    @events = []
  end

  def process_event(name, action, parameters)
    @events << [name, action, parameters]
  end
end

class EventTest < Minitest::Test
  describe RocketJob::Event do
    before do
      reset_subscribers
    end

    after do
      reset_subscribers
    end

    # The subscriber registry is class level state shared across the process,
    # so reset it between tests to keep them isolated.
    def reset_subscribers
      empty = Concurrent::Map.new { Concurrent::Array.new }
      RocketJob::Event.instance_variable_set(:@subscribers, empty)
    end

    describe "validations" do
      it "requires a name" do
        event = RocketJob::Event.new

        refute_predicate event, :valid?
        assert_predicate event.errors[:name], :present?
      end

      it "is valid with a name" do
        assert_predicate RocketJob::Event.new(name: "/rocket_job/server"), :valid?
      end
    end

    describe ".subscribe" do
      it "registers a subscriber and returns its object id as a handle" do
        subscriber = EventTestRecorder.new
        handle     = RocketJob::Event.subscribe(subscriber)

        assert_equal subscriber.object_id, handle
      end

      it "yields the subscriber and unsubscribes when the block completes" do
        subscriber = EventTestRecorder.new
        yielded    = nil

        RocketJob::Event.subscribe(subscriber) do |s|
          yielded = s
          registered = RocketJob::Event.instance_variable_get(:@subscribers)["EventTestRecorder"]

          assert_includes registered, subscriber
        end

        assert_equal subscriber, yielded
        registered = RocketJob::Event.instance_variable_get(:@subscribers)["EventTestRecorder"]

        refute_includes registered, subscriber
      end

      it "unsubscribes even when the block raises" do
        subscriber = EventTestRecorder.new
        assert_raises(RuntimeError) do
          RocketJob::Event.subscribe(subscriber) { raise "kaboom" }
        end
        registered = RocketJob::Event.instance_variable_get(:@subscribers)["EventTestRecorder"]

        refute_includes registered, subscriber
      end
    end

    describe ".unsubscribe" do
      it "removes only the subscriber matching the handle" do
        keep   = EventTestRecorder.new
        remove = EventTestRecorder.new
        RocketJob::Event.subscribe(keep)
        handle = RocketJob::Event.subscribe(remove)

        RocketJob::Event.unsubscribe(handle)

        registered = RocketJob::Event.instance_variable_get(:@subscribers)["EventTestRecorder"]

        assert_includes registered, keep
        refute_includes registered, remove
      end
    end

    describe ".process_event" do
      it "dispatches the action to a subscriber registered for the event name" do
        subscriber = EventTestRecorder.new
        RocketJob::Event.subscribe(subscriber)

        event = RocketJob::Event.new(name: "EventTestRecorder", action: :hello, parameters: {"message" => "hi"})
        RocketJob::Event.process_event(event)

        assert_equal [:hello, "hi"], subscriber.received
      end

      it "notifies all-events subscribers via process_event" do
        listener = EventTestAllEvents.new
        RocketJob::Event.subscribe(listener)

        event = RocketJob::Event.new(name: "EventTestRecorder", action: :hello, parameters: {"message" => "hi"})
        RocketJob::Event.process_event(event)

        assert_equal [["EventTestRecorder", :hello, {"message" => "hi"}]], listener.events
      end

      it "does nothing when there are no subscribers for the event name" do
        event = RocketJob::Event.new(name: "Nobody", action: :hello)
        # Should not raise.
        assert_nil RocketJob::Event.process_event(event)
      end

      it "rescues exceptions raised by a subscriber" do
        subscriber = EventTestRecorder.new
        RocketJob::Event.subscribe(subscriber)

        event = RocketJob::Event.new(name: "EventTestRecorder", action: :boom)
        # process_action swallows the error, so process_event completes cleanly.
        RocketJob::Event.process_event(event)
      end
    end

    describe "capped collection" do
      before do
        RocketJob::Event.collection.drop
      end

      after do
        RocketJob::Event.collection.drop
      end

      describe ".collection_exists?" do
        it "is false before the collection is created" do
          refute_predicate RocketJob::Event, :collection_exists?
        end

        it "is true once the collection is created" do
          RocketJob::Event.create_capped_collection

          assert_predicate RocketJob::Event, :collection_exists?
        end
      end

      describe ".create_capped_collection" do
        it "creates a capped collection when none exists" do
          RocketJob::Event.create_capped_collection

          assert_predicate RocketJob::Event.collection, :capped?
        end

        it "converts an existing non-capped collection to capped" do
          # Create a plain, non-capped collection first.
          RocketJob::Event.create!(name: "/rocket_job/server", action: :seed)

          refute_predicate RocketJob::Event.collection, :capped?

          RocketJob::Event.create_capped_collection

          assert_predicate RocketJob::Event.collection, :capped?
        end
      end
    end

    describe "polling collection" do
      before do
        RocketJob::Event.collection.drop
      end

      after do
        RocketJob::Event.collection.drop
      end

      describe ".create_polling_collection" do
        it "creates a regular, non-capped collection" do
          RocketJob::Event.create_polling_collection

          assert_predicate RocketJob::Event, :collection_exists?
          refute_predicate RocketJob::Event.collection, :capped?
        end

        it "creates a TTL index on created_at" do
          RocketJob::Event.create_polling_collection

          ttl_index = RocketJob::Event.collection.indexes.find { |i| i["key"] == {"created_at" => 1} }

          refute_nil ttl_index, "expected a created_at index"
          assert_equal RocketJob::Event.event_retention_seconds, ttl_index["expireAfterSeconds"]
        end

        it "is idempotent when called repeatedly" do
          RocketJob::Event.create_polling_collection
          # Should not raise on the second call.
          RocketJob::Event.create_polling_collection

          assert_predicate RocketJob::Event, :collection_exists?
        end
      end

      describe ".poll_once" do
        before do
          RocketJob::Event.create_polling_collection
        end

        it "yields events newer than the start time" do
          start = Time.now.utc - 1
          RocketJob::Event.create!(name: "EventTestRecorder", action: :hello)

          seen = []
          RocketJob::Event.poll_once(start) { |event| seen << event }

          assert_equal ["EventTestRecorder"], seen.map(&:name)
        end

        it "ignores events at or before the start time" do
          RocketJob::Event.create!(name: "EventTestRecorder", action: :hello)
          future = Time.now.utc + 60

          seen = []
          RocketJob::Event.poll_once(future) { |event| seen << event }

          assert_empty seen
        end

        it "returns the last _id as the watermark and uses it on the next pass" do
          start = Time.now.utc - 1
          first = RocketJob::Event.create!(name: "EventTestRecorder", action: :hello)

          watermark = RocketJob::Event.poll_once(start) { |_event| nil }

          assert_equal first.id, watermark

          # A second pass from the watermark sees only newer events, not the first one.
          second = RocketJob::Event.create!(name: "EventTestRecorder", action: :hello)

          seen = []
          RocketJob::Event.poll_once(start, watermark) { |event| seen << event }

          assert_equal [second.id], seen.map(&:id)
        end

        it "does not skip events sharing a created_at timestamp" do
          start = Time.now.utc - 1
          stamp = Time.now.utc
          two   = Array.new(2) { RocketJob::Event.create!(name: "EventTestRecorder", action: :hello, created_at: stamp) }

          seen = []
          RocketJob::Event.poll_once(start) { |event| seen << event }

          assert_equal two.map(&:id).sort, seen.map(&:id).sort
        end
      end
    end
  end
end

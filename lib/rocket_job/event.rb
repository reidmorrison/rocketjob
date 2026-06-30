require "concurrent-ruby"

module RocketJob
  # RocketJob::Event
  #
  # Publish and Subscribe to events. Events are published immediately and usually consumed
  # almost immediately by all subscriber processes.
  class Event
    include SemanticLogger::Loggable
    include Plugins::Document
    include Mongoid::Timestamps

    ALL_EVENTS = "*".freeze

    # MongoDB OperationFailure codes that are safe to ignore when concurrently
    # creating the polling collection and its TTL index:
    #   48 NamespaceExists, 85 IndexOptionsConflict, 86 IndexKeySpecsConflict.
    IGNORABLE_CREATE_CODES = [48, 85, 86].freeze

    # Capped collection long polling interval.
    class_attribute :long_poll_seconds, instance_accessor: false
    self.long_poll_seconds = 300

    # Capped collection size.
    # Only used the first time the collection is created.
    #
    # Default: 128MB.
    class_attribute :capped_collection_size, instance_accessor: false
    self.capped_collection_size = 128 * 1024 * 1024

    # Event listener strategy:
    #   :capped  - Tail a capped collection with a tailable cursor (default).
    #              Lowest latency, but requires a data store that supports capped
    #              collections and tailable cursors (i.e. a real MongoDB server).
    #   :polling - Poll a regular collection for new events. Slightly higher latency
    #              (bounded by `poll_interval`), but works on any MongoDB-compatible
    #              store, including AWS DocumentDB which has no capped collections.
    class_attribute :listener_strategy, instance_accessor: false
    self.listener_strategy = :capped

    # Polling strategy: seconds to wait between polls for new events.
    class_attribute :poll_interval, instance_accessor: false
    self.poll_interval = 1

    # Polling strategy: seconds an event is retained before a TTL index removes it.
    # Must comfortably exceed the longest expected listener downtime so that a
    # restarting server can still recover events published while it was away.
    #
    # Default: 1 hour.
    class_attribute :event_retention_seconds, instance_accessor: false
    self.event_retention_seconds = 60 * 60

    # Mandatory Event Name
    #   Examples:
    #     '/rocket_job/config'
    #     '/rocket_job/server'
    #     '/rocket_job/worker'
    field :name, type: String

    # Event Action
    #   Examples:
    #     :shutdown
    #     :pause
    #     :updated
    field :action, type: Mongoid::StringifiedSymbol

    # Hash Parameters to be sent with the event (event specific).
    field :parameters, type: Hash

    validates_presence_of :name

    store_in collection: "rocket_job.events"
    index({created_at: 1}, background: true)

    # Add a subscriber for its events.
    # Returns a handle to the subscription that can be used to unsubscribe
    # this particular subscription
    #
    # Example:
    # def MySubscriber
    #   include RocketJob::Subscriber
    #
    #   def hello
    #     logger.info "Hello Action Received"
    #   end
    #
    #   def show(message:)
    #     logger.info "Received: #{message}"
    #   end
    # end
    #
    # MySubscriber.subscribe
    def self.subscribe(subscriber)
      if block_given?
        begin
          handle = add_subscriber(subscriber)
          yield(subscriber)
        ensure
          unsubscribe(handle) if handle
        end
      else
        add_subscriber(subscriber)
      end
    end

    # Unsubscribes a previous subscription
    def self.unsubscribe(handle)
      @subscribers.each_value { |v| v.delete_if { |i| i.object_id == handle } }
    end

    # Indefinitely watch for new events, dispatching each to its subscribers.
    #   time: the start time from which to start looking for new events.
    def self.listener(time: @load_time)
      Thread.current.name = "rocketjob event"

      case listener_strategy
      when :capped
        create_capped_collection
        logger.info("Event listener started (capped collection)")
        tail_capped_collection(time) { |event| process_event(event) }
      when :polling
        create_polling_collection
        logger.info("Event listener started (polling, interval: #{poll_interval}s)")
        poll_collection(time) { |event| process_event(event) }
      else
        raise(ArgumentError, "Unknown RocketJob::Event.listener_strategy: #{listener_strategy.inspect}")
      end
    rescue Exception => e
      logger.error("#listener Event listener is terminating due to unhandled exception", e)
      raise(e)
    end

    # Create the capped collection only if it does not exist.
    # Drop the collection before calling this method to re-create it.
    def self.create_capped_collection(size: capped_collection_size)
      if collection_exists?
        convert_to_capped_collection(size) unless collection.capped?
      else
        collection.client[collection_name, {capped: true, size: size}].create
      end
    end

    @load_time   = Time.now.utc
    @subscribers = Concurrent::Map.new { Concurrent::Array.new }

    def self.add_subscriber(subscriber)
      name               = subscriber.class.event_name
      @subscribers[name] = @subscribers[name] << subscriber
      subscriber.object_id
    end

    def self.tail_capped_collection(time)
      with(socket_timeout: long_poll_seconds + 10) do
        filter = {created_at: {"$gt" => time}}
        collection.
          find(filter).
          await_data.
          cursor_type(:tailable_await).
          max_await_time_ms(long_poll_seconds * 1000).
          sort("$natural" => 1).
          each do |doc|
          event = Mongoid::Factory.from_db(Event, doc)
          # Recovery will occur from after the last message read
          time = event.created_at
          yield(event)
        end
      end
    rescue Mongo::Error::SocketError, Mongo::Error::SocketTimeoutError, Mongo::Error::OperationFailure, Timeout::Error => e
      logger.info("Creating a new cursor and trying again: #{e.class.name} #{e.message}")
      retry
    end

    # Create the regular (non-capped) collection used by the polling strategy,
    # along with a TTL index that expires old events.
    #
    # Safe to call repeatedly: it never drops data, and tolerates the collection
    # and index already existing.
    def self.create_polling_collection
      collection.client[collection_name].create unless collection_exists?
      collection.indexes.create_one({created_at: 1}, expire_after: event_retention_seconds)
    rescue Mongo::Error::OperationFailure => e
      # Ignore "collection already exists" and "index already exists" races between
      # multiple servers starting at once. Anything else is a real error.
      raise(e) unless IGNORABLE_CREATE_CODES.include?(e.code)
    end

    # Indefinitely poll a regular collection for new events.
    #   time: the start time from which to start looking for new events.
    #
    # After the first poll the `_id` of the last event seen is used as the
    # watermark, which is monotonic and unique, so events sharing a `created_at`
    # timestamp are never skipped.
    def self.poll_collection(time, &block)
      last_id = nil
      loop do
        last_id = poll_once(time, last_id, &block)
        sleep(poll_interval)
      end
    rescue Mongo::Error::SocketError, Mongo::Error::SocketTimeoutError, Mongo::Error::OperationFailure, Timeout::Error => e
      logger.info("Polling failed, retrying: #{e.class.name} #{e.message}")
      sleep(poll_interval)
      retry
    end

    # Perform a single polling pass, yielding every event newer than the watermark
    # and returning the new watermark (the `_id` of the last event seen, or the
    # supplied `last_id` when no new events were found).
    def self.poll_once(time, last_id = nil)
      filter = last_id ? {_id: {"$gt" => last_id}} : {created_at: {"$gt" => time}}
      collection.find(filter).sort(_id: 1).each do |doc|
        last_id = doc["_id"]
        yield(Mongoid::Factory.from_db(Event, doc))
      end
      last_id
    end

    # Process a new event, calling registered subscribers.
    def self.process_event(event)
      logger.info("Event Received", event.attributes)

      if @subscribers.key?(event.name)
        @subscribers[event.name].each { |subscriber| subscriber.process_action(event.action, event.parameters) }
      end

      if @subscribers.key?(ALL_EVENTS)
        @subscribers[ALL_EVENTS].each { |subscriber| subscriber.process_event(event.name, event.action, event.parameters) }
      end
    rescue StandardError => e
      logger.error("Unknown subscriber. Continuing..", e)
    end

    def self.collection_exists?
      collection.database.collection_names.include?(collection_name.to_s)
    end

    # Convert a non-capped collection to capped
    def self.convert_to_capped_collection(size)
      collection.database.command("convertToCapped" => collection_name.to_s, "size" => size)
    end
  end
end

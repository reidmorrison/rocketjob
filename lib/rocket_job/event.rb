require 'concurrent-ruby'

module RocketJob
  # RocketJob::Event
  #
  # Publish and Subscribe to events. Events are published immediately and usually consumed
  # almost immediately by all subscriber processes.
  class Event
    include SemanticLogger::Loggable
    include Plugins::Document
    include Mongoid::Timestamps

    WILDCARD = '*'.freeze

    # Capped collection long polling interval.
    class_attribute :long_poll_seconds, instance_accessor: false
    self.long_poll_seconds = 300

    # Capped collection size.
    # Only used the first time the collection is created.
    #
    # Default: 128MB.
    class_attribute :capped_collection_size, instance_accessor: false
    self.capped_collection_size = 128 * 1024 * 1024

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
    field :action, type: Symbol

    # Hash Parameters to be sent with the event (event specific).
    field :parameters, type: Hash

    validates_presence_of :name

    store_in collection: 'rocket_job.events'
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

    # Indefinitely tail the capped collection looking for new events.
    #   time: the start time from which to start looking for new events.
    def self.listener(time: @load_time)
      Thread.current.name = 'rocketjob event'
      create_capped_collection

      logger.info('Event listener started')
      tail_capped_collection(time) { |event| process_event(event) }
    rescue Exception => exc
      logger.error('#listener Event listener is terminating due to unhandled exception', exc)
      raise(exc)
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

    private

    @load_time   = Time.now.utc
    @subscribers = Concurrent::Map.new { Concurrent::Array.new }

    def self.add_subscriber(subscriber)
      name               = subscriber.class.name
      @subscribers[name] = @subscribers[name] << subscriber
      subscriber.object_id
    end

    def self.tail_capped_collection(time)
      with(socket_timeout: long_poll_seconds + 10) do
        filter = {created_at: {'$gt' => time}}
        collection.
          find(filter).
          await_data.
          cursor_type(:tailable_await).
          max_await_time_ms(long_poll_seconds * 1000).
          sort('$natural' => 1).
          each do |doc|
          event = Mongoid::Factory.from_db(Event, doc)
          # Recovery will occur from after the last message read
          time = event.created_at
          yield(event)
        end
      end
    rescue Mongo::Error::SocketError, Mongo::Error::SocketTimeoutError, Mongo::Error::OperationFailure, Timeout::Error => exc
      logger.info("Creating a new cursor and trying again: #{exc.class.name} #{exc.message}")
      retry
    end

    # Process a new event, calling registered subscribers.
    def self.process_event(event)
      logger.info('Event Received', event.attributes)

      if @subscribers.key?(event.name)
        @subscribers[event.name].each { |subscriber| subscriber.process_action(event.action, event.parameters) }
      end

      if @subscribers.key?(WILDCARD)
        @subscribers[WILDCARD].each { |subscriber| subscriber.process_event(event.name, event.action, event.parameters) }
      end
    rescue StandardError => exc
      logger.error('Unknown subscriber. Continuing..', exc)
    end

    def self.collection_exists?
      collection.database.collection_names.include?(collection_name.to_s)
    end

    # Convert a non-capped collection to capped
    def self.convert_to_capped_collection(size)
      collection.database.command('convertToCapped' => collection_name.to_s, 'size' => size)
    end
  end
end

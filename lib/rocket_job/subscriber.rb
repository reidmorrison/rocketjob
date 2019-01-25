require 'active_support/concern'

module RocketJob
  # Mix-in to publish and subscribe to events.
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
  #
  #   # If `message` is not supplied it defaults to "Hello World"
  #   def show_default(message: "Hello World")
  #     logger.info "Received: #{message}"
  #   end
  # end
  #
  # MySubscriber.subscribe
  module Subscriber
    extend ActiveSupport::Concern

    # Test Mode
    # Bypasses publishing the event and calls the subscribers directly
    def self.test_mode!
      @test_mode = true
    end

    def self.test_mode?
      @test_mode
    end

    @test_mode = false

    included do
      include SemanticLogger::Loggable

      def self.publish(action, **parameters)
        raise(ArgumentError, "Invalid action: #{action}") unless public_method_defined?(action)

        event = Event.new(name: name, action: action, parameters: parameters)
        Subscriber.test_mode? ? Event.process_event(event) : event.save!
      end

      def self.subscribe(*args, &block)
        instance = new(*args)
        Event.subscribe(instance, &block)
      end
    end

    def process_action(action, parameters = nil)
      unless public_methods.include?(action)
        logger.warn("Ignoring unknown action: #{action}")
        return
      end

      args = (method(action).arity == 0) || parameters.nil? ? nil : parameters.symbolize_keys
      args ? public_send(action, **args) : public_send(action)
    rescue StandardError => exc
      logger.error('Exception calling subscriber. Resuming..', exc)
    end

    def process_event(name, action, parameters = nil)
      raise(NotImplementedError)
    end
  end
end

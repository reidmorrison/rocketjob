require 'active_support/concern'
require 'concurrent'

module RocketJob
  class Supervisor
    module Shutdown
      extend ActiveSupport::Concern

      included do
        # Set shutdown indicator for this server process
        def self.shutdown!
          @shutdown.set
          event!
        end

        # Returns [true|false] whether the shutdown indicator has been set for this server process
        def self.shutdown?
          @shutdown.set?
        end

        # An event has occured
        def self.event!
          @event.set
        end

        # Returns [true|false] whether the shutdown indicator was set before the timeout was reached
        def self.wait_for_event(timeout = nil)
          @event.wait(timeout)
          @event.reset
        end

        @shutdown = Concurrent::Event.new
        @event    = Concurrent::Event.new

        # Register handlers for the various signals
        # Term:
        #   Perform clean shutdown
        #
        def self.register_signal_handlers
          Signal.trap 'SIGTERM' do
            Thread.new do
              shutdown!
              message = 'Shutdown signal (SIGTERM) received. Will shutdown as soon as active jobs/slices have completed.'
              logger.info(message)
            end
          end

          Signal.trap 'INT' do
            Thread.new do
              shutdown!
              message = 'Shutdown signal (INT) received. Will shutdown as soon as active jobs/slices have completed.'
              logger.info(message)
            end
          end
        rescue StandardError
          logger.warn 'SIGTERM handler not installed. Not able to shutdown gracefully'
        end

        private_class_method :register_signal_handlers
      end
    end
  end
end

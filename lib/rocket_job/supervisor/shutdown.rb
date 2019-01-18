require 'active_support/concern'
require 'concurrent'

module RocketJob
  class Supervisor
    module Shutdown
      extend ActiveSupport::Concern

      included do
        # On CRuby the 'concurrent-ruby-ext' gem may not be loaded
        if defined?(Concurrent::JavaAtomicBoolean) || defined?(Concurrent::CAtomicBoolean)
          # Returns [true|false] whether the shutdown indicator has been set for this server process
          def self.shutdown?
            @shutdown.value
          end

          # Set shutdown indicator for this server process
          def self.shutdown!
            @shutdown.make_true
          end

          @shutdown = Concurrent::AtomicBoolean.new(false)
        else
          # Returns [true|false] whether the shutdown indicator has been set for this server process
          def self.shutdown?
            @shutdown
          end

          # Set shutdown indicator for this server process
          def self.shutdown!
            @shutdown = true
          end

          @shutdown = false
        end

        # Register handlers for the various signals
        # Term:
        #   Perform clean shutdown
        #
        def self.register_signal_handlers
          Signal.trap 'SIGTERM' do
            shutdown!
            message = 'Shutdown signal (SIGTERM) received. Will shutdown as soon as active jobs/slices have completed.'
            # Logging uses a mutex to access Queue on CRuby
            defined?(JRuby) ? logger.warn(message) : puts(message)
          end

          Signal.trap 'INT' do
            shutdown!
            message = 'Shutdown signal (INT) received. Will shutdown as soon as active jobs/slices have completed.'
            # Logging uses a mutex to access Queue on CRuby
            defined?(JRuby) ? logger.warn(message) : puts(message)
          end
        rescue StandardError
          logger.warn 'SIGTERM handler not installed. Not able to shutdown gracefully'
        end

        private_class_method :register_signal_handlers
      end

      # Returns [Boolean] whether the server is shutting down
      def shutdown?
        self.class.shutdown? || !server.running?
      end
    end
  end
end

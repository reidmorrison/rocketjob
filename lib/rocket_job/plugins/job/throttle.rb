require 'active_support/concern'

module RocketJob
  module Plugins
    module Job
      # Rocket Job Throttling Framework.
      #
      # Example:
      #   # Do not run this job when the MySQL slave delay exceeds 5 minutes.
      #   class MyJob < RocketJob
      #     # Define a custom mysql throttle
      #     # Prevents all jobs of this class from running on the current server.
      #     define_throttle :mysql_throttle_exceeded?
      #
      #     def perform
      #       # ....
      #     end
      #
      #     private
      #
      #     # Returns true if the MySQL slave delay exceeds 5 minutes
      #     def mysql_throttle_exceeded?
      #       status        = ActiveRecord::Base.connection.connection.select_one('show slave status')
      #       seconds_delay = Hash(status)['Seconds_Behind_Master'].to_i
      #       seconds_delay >= 300
      #     end
      #   end
      module Throttle
        extend ActiveSupport::Concern

        included do
          class_attribute :rocket_job_throttles
          self.rocket_job_throttles = []
        end

        module ClassMethods
          # Add a new throttle.
          #
          # Parameters:
          #   method_name: [Symbol]
          #     Name of method to call to evaluate whether a throttle has been exceeded.
          #     Note: Must return true or false.
          #   filter: [Symbol|Proc]
          #     Name of method to call to return the filter when the throttle has been exceeded.
          #     Or, a block that will return the filter.
          #     Default: :throttle_filter_class (Throttle all jobs of this class)
          #
          # Note: LIFO: The last throttle to be defined is executed first.
          def define_throttle(method_name, filter: :throttle_filter_class)
            raise(ArgumentError, "Filter for #{method_name} must be a Symbol or Proc") unless filter.is_a?(Symbol) || filter.is_a?(Proc)
            raise(ArgumentError, "Cannot define #{method_name} twice, undefine previous throttle first") if rocket_job_throttles.find { |throttle| throttle.method_name == method_name}

            rocket_job_throttles.unshift(ThrottleDefinition.new(method_name, filter))
          end

          # Undefine a previously defined throttle
          def undefine_throttle(method_name)
            rocket_job_throttles.delete_if { |throttle| throttle.method_name }
          end
        end

        # Default throttle to use when the throttle is exceeded.
        # When the throttle has been exceeded all jobs of this class will be ignored until the
        # next refresh. `RocketJob::Config::re_check_seconds` which by default is 60 seconds.
        def throttle_filter_class
          {:_type.nin => [self.class.name]}
        end

        # Filter out only this instance of the job.
        # When the throttle has been exceeded this job will be ignored by this server until the next refresh.
        # `RocketJob::Config::re_check_seconds` which by default is 60 seconds.
        def throttle_filter_id
          {:id.nin => [id]}
        end

        private

        ThrottleDefinition = Struct.new(:method_name, :filter)

        # Returns the matching filter, or nil if no throttles were triggered.
        def rocket_job_evaluate_throttles
          rocket_job_throttles.each do |throttle|
            # Throttle exceeded?
            if send(throttle.method_name)
              logger.debug { "Throttle: #{throttle.method_name} has been exceeded. #{self.class.name}:#{id}" }
              filter = throttle.filter
              return filter.is_a?(Proc) ? filter.call(self) : send(filter)
            end
          end
          nil
        end

      end

    end
  end
end

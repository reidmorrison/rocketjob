require "active_support/concern"
require 'sync_attr'

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
      #       status        = ActiveRecord::Base.connection.select_one('show slave status')
      #       seconds_delay = Hash(status)['Seconds_Behind_Master'].to_i
      #       seconds_delay >= 300
      #     end
      #   end
      module Throttle
        extend ActiveSupport::Concern

        included do
          class_attribute :rocket_job_throttles
        end

        module ClassMethods
          # Add a new throttle.
          #
          # Parameters:
          #   method_name: [Symbol]
          #     Name of method to call to evaluate whether a throttle has been exceeded.
          #     Note: Must return true or false.
          #
          #   filter: [Symbol|Proc]
          #     Name of method to call to return the filter when the throttle has been exceeded.
          #     Or, a block that will return the filter.
          #     Default: :throttle_filter_class (Throttle all jobs of this class)
          #
          # Note: Throttles are executed in the order they are defined.
          def define_throttle(method_name, filter: :throttle_filter_class)
            # Duplicate to prevent modifying parent class throttles
            definitions = rocket_job_throttles ? rocket_job_throttles.dup : ThrottleDefinitions.new
            definitions.add(method_name, filter)
            self.rocket_job_throttles = definitions
          end

          # Undefine a previously defined throttle
          def undefine_throttle(method_name)
            return unless rocket_job_throttles

            definitions = rocket_job_throttles.dup
            definitions.remove(method_name)
            self.rocket_job_throttles = definitions
          end

          # Has a throttle been defined?
          def throttle?(method_name)
            rocket_job_throttles&.exist?(method_name)
          end
        end

        # Default throttle to use when the throttle is exceeded.
        # When the throttle has been exceeded all jobs of this class will be ignored until the
        # next refresh. `RocketJob::Config.re_check_seconds` which by default is 60 seconds.
        def throttle_filter_class
          {:_type.nin => [self.class.name]}
        end

        # Filter out only this instance of the job.
        # When the throttle has been exceeded this job will be ignored by this server until the next refresh.
        # `RocketJob::Config.re_check_seconds` which by default is 60 seconds.
        def throttle_filter_id
          {:id.nin => [id]}
        end
      end
    end
  end
end

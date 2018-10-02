require 'active_support/concern'

module RocketJob
  module Batch
    # Rocket Job Batch Throttling Framework.
    #
    # Example:
    #   # Do not run any slices for this job when the MySQL slave delay exceeds 5 minutes.
    #   class MyJob < RocketJob
    #     include RocketJob::Batch
    #
    #     # Define a custom mysql throttle
    #     # Prevents all jobs of this class from running on the current server.
    #     define_batch_throttle :mysql_throttle_exceeded?
    #
    #     def perform(record)
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
        class_attribute :rocket_job_batch_throttles
        self.rocket_job_batch_throttles = []
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
        # Note: Throttles are executed in the order they are defined.
        def define_batch_throttle(method_name, filter: :throttle_filter_class)
          raise(ArgumentError, "Filter for #{method_name} must be a Symbol or Proc") unless filter.is_a?(Symbol) || filter.is_a?(Proc)
          raise(ArgumentError, "Cannot define #{method_name} twice, undefine previous throttle first") if rocket_job_batch_throttles.find { |throttle| throttle.method_name == method_name }

          self.rocket_job_batch_throttles += [ThrottleDefinition.new(method_name, filter)]
        end

        # Undefine a previously defined throttle
        def undefine_batch_throttle(method_name)
          rocket_job_batch_throttles.delete_if { |throttle| throttle.method_name }
        end

        # Has a throttle been defined?
        def has_batch_throttle?(method_name)
          rocket_job_batch_throttles.find { |throttle| throttle.method_name == method_name }
        end
      end

      private

      ThrottleDefinition = Struct.new(:method_name, :filter)

      # Returns the matching filter, or nil if no throttles were triggered.
      def rocket_job_batch_evaluate_throttles(slice)
        rocket_job_batch_throttles.each do |throttle|
          throttle_exceeded = method(throttle.method_name).arity == 0 ? send(throttle.method_name) : send(throttle.method_name, slice)
          if throttle_exceeded
            logger.debug { "Batch Throttle: #{throttle.method_name} has been exceeded. #{self.class.name}:#{id}" }
            filter = throttle.filter
            return filter.is_a?(Proc) ? filter.call(self) : send(filter)
          end
        end
        nil
      end

    end
  end
end

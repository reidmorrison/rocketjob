# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Plugins
    module Job
      # Throttle number of jobs of a specific class that are processed at the same time.
      #
      # Example:
      #   class MyJob < RocketJob
      #     # Maximum number of workers to process instances of this job at the same time.
      #     self.throttle_max_workers = 25
      #
      #     def perform
      #       # ....
      #     end
      #   end
      #
      # Notes:
      # - The actual number will be around this value, it con go over slightly and
      #   can drop depending on check interval can drop slightly below this value.
      # - By avoid hard locks and counters performance can be maintained while still
      #   supporting good enough throttling.
      # - If throughput is not as important as preventing brief spikes when many
      #   workers are running, add a double check into the perform:
      #     class MyJob < RocketJob
      #       self.throttle_max_workers = 25
      #
      #       def perform
      #         # (Optional) Prevent a brief spike from exceeding the wax worker throttle
      #         self.class.throttle_double_check
      #
      #         # ....
      #       end
      #     end
      module Throttle
        extend ActiveSupport::Concern

        included do
          class_attribute :throttle_max_workers
          self.throttle_max_workers = nil
        end

        # Throttle to add when the throttle is exceeded
        def throttle_filter
          {:_type.nin => self.class.name}
        end

        # Returns [Boolean] whether the throttle for this job has been exceeded
        def throttle_exceeded?
          throttle_max_workers && (throttle_max_workers != 0) ? (self.class.running.count >= throttle_max_workers) : false
        end

        # Prevent a brief spike from exceeding the wax worker throttle
        def throttle_double_check(check_seconds = 1)
          while !throttle_exceeded?
            sleep check_seconds
          end
        end

        private

        # Merge filter(s)
        def throttle_merge_filter(target, source)
          source.each_key do |k, v|
            previous  = target[k]
            target[k] = previous ? (Array(previous) << v) : v
          end
        end

      end

    end
  end
end

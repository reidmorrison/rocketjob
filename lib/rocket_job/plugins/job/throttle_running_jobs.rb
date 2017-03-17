require 'active_support/concern'

module RocketJob
  module Plugins
    module Job
      # Throttle the number of jobs of a specific class that are processed at the same time.
      #
      # Example:
      #   class MyJob < RocketJob
      #     # Maximum number of jobs of this class to process at the same time.
      #     self.throttle_running_jobs = 25
      #
      #     def perform
      #       # ....
      #     end
      #   end
      #
      # Notes:
      # - The actual number will be around this value, it can go over slightly and
      #   can drop depending on check interval can drop slightly below this value.
      # - By avoiding hard locks and counters performance can be maintained while still
      #   supporting good enough quantity throttling.
      module ThrottleRunningJobs
        extend ActiveSupport::Concern

        included do
          # Limit number of jobs running of this class.
          class_attribute :throttle_running_jobs
          self.throttle_running_jobs = nil

          define_throttle :throttle_running_jobs_exceeded?
        end

        private

        # Returns [Boolean] whether the throttle for this job has been exceeded
        def throttle_running_jobs_exceeded?
          throttle_running_jobs &&
            (throttle_running_jobs != 0) &&
              (self.class.running.where(:id.ne => id).count >= throttle_running_jobs)
        end
      end
    end
  end
end

require "active_support/concern"

module RocketJob
  module Plugins
    module Job
      # Throttle the number of jobs of a specific class that are processed at the same time.
      #
      # Example:
      #   class MyJob < RocketJob::Job
      #     # Maximum number of jobs of this class to process at the same time.
      #     self.throttle_running_jobs = 25
      #
      #     def perform
      #       # ....
      #     end
      #   end
      #
      # Notes:
      # - The number of running jobs will not exceed this value.
      # - It may appear that a job is running briefly over this limit, but then is immediately back into queued state.
      #   This is expected behavior and is part of the check to ensure this value is not exceeded.
      #   The worker grabs the job and only then verifies the throttle, this is to prevent any other worker
      #   from attempting to grab the job, which would have exceeded the throttle.
      module ThrottleRunningJobs
        extend ActiveSupport::Concern

        included do
          # Limit number of jobs running of this class.
          class_attribute :throttle_running_jobs
          self.throttle_running_jobs = nil

          # Allow jobs to be throttled by group name instance of the job class name.
          field :throttle_group, type: String, class_attribute: true, user_editable: true, copy_on_restart: true

          define_throttle :throttle_running_jobs_exceeded?
        end

        private

        # Returns [true|false] whether the throttle for this job has been exceeded
        def throttle_running_jobs_exceeded?
          return false unless throttle_running_jobs&.positive?

          RocketJob::Job.with(read: {mode: :primary}) do |conn|
            query = throttle_running_jobs_base_query
            throttle_group ? query["throttle_group"] = throttle_group : query["_type"] = self.class.name
            conn.running.where(query).count >= throttle_running_jobs
          end
        end

        def throttle_running_jobs_base_query
          {:id.ne => id}
        end
      end
    end
  end
end

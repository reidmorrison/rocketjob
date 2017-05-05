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

          define_throttle :throttle_running_jobs_exceeded?
        end

        private

        # Returns [Boolean] whether the throttle for this job has been exceeded
        def throttle_running_jobs_exceeded?
          throttle_running_jobs &&
            (throttle_running_jobs != 0) &&
              # Cannot use class since it will include instances of parent job classes.
              (RocketJob::Job.running.where('_type' => self.class.name, :id.ne => id).count >= throttle_running_jobs)
        end
      end
    end
  end
end

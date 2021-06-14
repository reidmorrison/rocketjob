require "active_support/concern"
module RocketJob
  module Plugins
    module Job
      # Prevent this job from starting, or a batch slice from starting if the dependant jobs are running.
      #
      # Features:
      # - Ensures dependant jobs won't run
      # When the throttle has been exceeded all jobs of this class will be ignored until the
      # next refresh. `RocketJob::Config::re_check_seconds` which by default is 60 seconds.
      module ThrottleDependantJobs
        extend ActiveSupport::Concern

        included do
          class_attribute :dependant_jobs
          self.dependant_jobs = nil

          define_throttle :dependant_job_exists?
          define_batch_throttle :dependant_job_exists? if respond_to?(:define_batch_throttle)
        end

        private

        # Checks if there are any dependant jobs are running
        def dependant_job_exists?
          return false if dependant_jobs.blank?

          jobs_count = RocketJob::Job.running.where(:_type.in => dependant_jobs).count
          return false if jobs_count.zero?

          logger.info(
            message: "#{jobs_count} Dependant Jobs are running from #{dependant_jobs.join(', ')}",
            metric:  "RocketJob/dependant_jobs_count"
          )
          true
        end
      end
    end
  end
end

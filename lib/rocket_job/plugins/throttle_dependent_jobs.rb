require "active_support/concern"
module RocketJob
  module Plugins
    # Prevent this job from starting, or a batch slice from starting if the dependent jobs are running.
    #
    # Features:
    # - Ensures dependent jobs won't run
    # When the throttle has been exceeded all jobs of this class will be ignored until the
    # next refresh. `RocketJob::Config::re_check_seconds` which by default is 60 seconds.
    module ThrottleDependentJobs
      extend ActiveSupport::Concern

      included do
        field :dependent_jobs, type: Array, class_attribute: true, user_editable: true, copy_on_restart: true

        define_throttle :dependent_jobs_running?
        define_batch_throttle :dependent_jobs_running? if respond_to?(:define_batch_throttle)
      end

      class_methods do
        def depends_on_job(*jobs)
          self.dependent_jobs = Array(jobs).collect(&:to_s)
        end
      end

      private

      # Checks if there are any dependent jobs are running
      def dependent_jobs_running?
        return false if dependent_jobs.blank?

        jobs_count = RocketJob::Job.running.where(:_type.in => dependent_jobs).count
        return false if jobs_count.zero?

        logger.info(
          message: "#{jobs_count} Dependent Jobs are running from #{dependent_jobs.join(', ')}",
          metric:  "#{self.class.name}/dependent_jobs_throttle"
        )
        true
      end
    end
  end
end

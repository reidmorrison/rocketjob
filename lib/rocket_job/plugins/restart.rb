require 'active_support/concern'

module RocketJob
  module Plugins
    # Automatically starts a new instance of this job anytime it fails, aborts, or completes.
    # Failed jobs are aborted so that they cannot be restarted.
    # On destroy this job is destroyed without starting a new copy. Abort the job first to get
    # it to start a new instance before destroying.
    # Include RocketJob::Plugins::Singleton to prevent multiple copies of a job from running at
    # the same time.
    #
    # Note:
    # - The job will not be restarted if:
    #   - A validation fails after cloning this job.
    #   - The job has expired.
    module Restart
      extend ActiveSupport::Concern

      included do
        # Attributes to exclude when copying across the attributes to the new instance
        class_attribute :rocket_job_restart_excludes
        self.rocket_job_restart_excludes = %w(_id state created_at started_at completed_at failure_count worker_name percent_complete exception result run_at record_count sub_state)

        after_abort :rocket_job_restart_new_instance
        after_complete :rocket_job_restart_new_instance
        after_fail :rocket_job_restart_abort
      end

      module ClassMethods
        def field(name, options)
          if options.delete(:copy_on_restart) == false
            self.rocket_job_restart_excludes += [name.to_sym] unless rocket_job_restart_excludes.include?(name.to_sym)
          end
          super(name, options)
        end
      end

      private

      # Run again in the future, even if this run fails with an exception
      def rocket_job_restart_new_instance
        return if expired?
        attrs = attributes.dup
        rocket_job_restart_excludes.each { |attr| attrs.delete(attr) }

        # Copy across run_at for future dated jobs
        attrs['run_at'] = run_at if run_at && (run_at > Time.now)

        rocket_job_restart_create(attrs)
      end

      def rocket_job_restart_abort
        new_record? ? abort : abort!
      end

      # Allow Singleton to prevent the creation of a new job if one is already running
      # Retry since the delete may not have persisted to disk yet.
      def rocket_job_restart_create(attrs, retry_limit = 3, sleep_interval = 0.1)
        count = 0
        while count < retry_limit
          job = self.class.create(attrs)
          if job.persisted?
            logger.info("Started a new job instance: #{job.id}")
            return true
          else
            logger.info('Job already active, retrying after a short sleep')
            sleep(sleep_interval)
          end
          count += 1
        end
        logger.warn('New job instance not started since one is already active')
        false
      end


    end
  end
end

require 'active_support/concern'

module RocketJob
  module Plugins
    # Automatically starts a new instance of this job anytime it fails, aborts, or completes.
    #
    # Notes:
    # * Restartable jobs automatically abort if they fail. This prevents the failed job from being retried.
    #   - To disable this behavior, add the following empty method:
    #        def rocket_job_restart_abort
    #        end
    # * On destroy this job is destroyed without starting a new instance.
    # * On Abort a new instance is created.
    # * Include `RocketJob::Plugins::Singleton` to prevent multiple copies of a job from running at
    #   the same time.
    # * The job will not be restarted if:
    #   - A validation fails after creating the new instance of this job.
    #   - The job has expired.
    # * Only the fields that have `copy_on_restart: true` will be passed onto the new instance of this job.
    #
    # Example:
    #
    # class RestartableJob < RocketJob::Job
    #   include RocketJob::Plugins::Restart
    #
    #   # Retain the completed job under the completed tab in Rocket Job Web Interface.
    #   self.destroy_on_complete = false
    #
    #   # Will be copied to the new job on restart.
    #   field :limit, type: Integer, copy_on_restart: true
    #
    #   # Will _not_ be copied to the new job on restart.
    #   field :list, type: Array, default: [1,2,3]
    #
    #   # Set run_at every time a new instance of the job is created.
    #   after_initialize set_run_at, if: :new_record?
    #
    #   def perform
    #     puts "The limit is #{limit}"
    #     puts "The list is #{list}"
    #     'DONE'
    #   end
    #
    #   private
    #
    #   # Run this job in 30 minutes.
    #   def set_run_at
    #     self.run_at = 30.minutes.from_now
    #   end
    # end
    #
    # job = RestartableJob.create!(limit: 10, list: [4,5,6])
    # job.reload.state
    # # => :queued
    #
    # job.limit
    # # => 10
    #
    # job.list
    # # => [4,5,6]
    #
    # # Wait 30 minutes ...
    #
    # job.reload.state
    # # => :completed
    #
    # # A new instance was automatically created.
    # job2 = RestartableJob.last
    # job2.state
    # # => :queued
    #
    # job2.limit
    # # => 10
    #
    # job2.list
    # # => [1,2,3]
    module Restart
      extend ActiveSupport::Concern

      included do
        after_abort :rocket_job_restart_new_instance
        after_complete :rocket_job_restart_new_instance
        after_fail :rocket_job_restart_abort
      end

      private

      # Run again in the future, even if this run fails with an exception
      def rocket_job_restart_new_instance
        if expired?
          logger.info('Job has expired. Not creating a new instance.')
          return
        end
        attributes = rocket_job_restart_attributes.each_with_object({}) { |attr, attrs| attrs[attr] = send(attr) }
        rocket_job_restart_create(attributes)
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
            logger.info("Created a new job instance: #{job.id}")
            return true
          else
            logger.info('Job already active, retrying after a short sleep')
            sleep(sleep_interval)
          end
          count += 1
        end
        logger.warn("New job instance not started: #{job.errors.messages.inspect}")
        false
      end
    end
  end
end

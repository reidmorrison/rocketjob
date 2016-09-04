# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Plugins
    # Automatically retry the job on failure.
    #
    # The following retry algorithm is used to automatically retry a job when it fails:
    # Failed jobs are aborted so that they cannot be restarted since a new instance has there are workers
    # available to run. For example if workers are busy working on higher priority jobs, then the job
    # will only run once those jobs have completed, or their priority lowered. Additionally, while the
    # job is queued no additional instances will be enqueued, even if the next cron interval has been reached.
    #
    # Note:
    # - After failure the job is scheduled to run again in the future.
    # - The job will not be retried if:
    #   - The job has expired.
    #   - The job fails validations.
    #   - The number of retry counts has been exceeded.
    # - To see the number of times a job has failed so far:
    #     job.failure_count
    #
    # Example:
    #
    # class MyJob < RocketJob::Job
    #   include RocketJob::Plugins::Retry
    #
    #   # Set the default retry_count
    #   self.max_retries = 3
    #
    #   def perform
    #     puts "DONE"
    #   end
    # end
    #
    # # Queue the job for processing using the default cron_schedule specified above
    # MyJob.create!
    #
    # # Replace the default retry_count
    # MyCronJob.create!(max_retries: 10)
    #
    # # Disable retries for this job instance
    # MyCronJob.create!(max_retries: 0)
    #
    module Retry
      extend ActiveSupport::Concern

      included do
        after_fail :rocket_job_retry

        # Maximum number of times to retry this job
        # 25 is approximately 3 weeks of retries
        field :max_retries, type: Integer, default: 25, class_attribute: true

        # List of times when this job failed
        field :failed_times, type: Array, default: []

        # Make max_retries editable in Rocket Job Mission Control
        public_rocket_job_properties :max_retries

        validates_presence_of :max_retries
      end

      # Returns [true|false] whether this job will be automatically retried on failure
      def rocket_job_retry_on_fail?
        failure_count > max_retries
      end

      private

      def rocket_job_retry
        # Failure count is incremented during before_fail
        return if expired? || !rocket_job_retry_on_fail?

        delay_seconds = rocket_job_retry_seconds_to_delay
        logger.info "Job failed, automatically retrying in #{delay_seconds} seconds. Retry count: #{failure_count}"

        now         = Time.now
        self.run_at = now + delay_seconds
        self.failed_times << now
        new_record? ? retry : retry!
      end

      # Prevent exception from being cleared on retry
      def rocket_job_clear_exception
        self.completed_at = nil
        self.exception    = nil unless rocket_job_retry_on_fail?
        self.worker_name  = nil
      end

      # Returns [Time] when to retry this job at
      # Same basic formula as Sidekiq and Delayed Job
      def rocket_job_retry_seconds_to_delay
        (failure_count ** 4) + 15 + (rand(30)*(failure_count+1))
      end

    end
  end
end

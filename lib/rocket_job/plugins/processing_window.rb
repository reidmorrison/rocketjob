require 'active_support/concern'

module RocketJob
  module Plugins
    # Ensure that a job will only run between certain hours of the day, regardless of when it was
    # created/enqueued. Useful for creating a job now that should only be processed later during a
    # specific time window. If the time window is already active the job is able to be processed
    # immediately.
    #
    # Example: Process this job on Monday’s between 8am and 10am.
    #
    # Example: Run this job on the 1st of every month from midnight for the entire day.
    #
    # Since the cron schedule supports time zones it is easy to setup jobs to run at UTC or any other time zone.
    #
    # Example:
    # # Only run the job between the hours of 8:30am and 8:30pm. If it is after 8:30pm schedule
    # # it to run at 8:30am the next day.
    # class BusinessHoursJob < RocketJob::Job
    #   include RocketJob::Plugins::ProcessingWindow
    #
    #   # The start of the processing window
    #   self.processing_schedule = "30 8 * * * America/New_York"
    #   # How long the processing window is:
    #   self..processing_duration = 12.hours
    #
    #   def perform
    #     # Job will only run between 8:30am and 8:30pm Eastern
    #   end
    # end
    #
    # Note:
    #   If a job is created/enqueued during the processing window, but due to busy/unavailable workers
    #   is not processed during the window, the current job will be re-queued for the beginning
    #   of the next processing window.
    module ProcessingWindow
      extend ActiveSupport::Concern

      included do
        field :processing_schedule, type: String, class_attribute: true
        field :processing_duration, type: Integer, class_attribute: true

        before_create :rocket_job_processing_window_set_run_at
        before_retry :rocket_job_processing_window_set_run_at
        after_start :rocket_job_processing_window_check

        validates_presence_of :processing_schedule, :processing_duration
        validates_each :processing_schedule do |record, attr, value|
          begin
            RocketJob::Plugins::Rufus::CronLine.new(value)
          rescue ArgumentError => exc
            record.errors.add(attr, exc.message)
          end
        end
      end

      # Returns [true|false] whether this job is currently inside its processing window
      def rocket_job_processing_window_active?
        time          = Time.now
        previous_time = rocket_job_processing_schedule.previous_time(time)
        # Inside previous processing window?
        previous_time + processing_duration > time
      end

      private

      # Only process this job if it is still in its processing window
      def rocket_job_processing_window_check
        return if rocket_job_processing_window_active?
        logger.warn("Processing window closed before job was processed. Job is re-scheduled to run at: #{rocket_job_processing_schedule.next_time}")
        self.worker_name ||= 'inline'
        self.requeue!(worker_name)
      end

      def rocket_job_processing_window_set_run_at
        self.run_at = rocket_job_processing_schedule.next_time unless rocket_job_processing_window_active?
      end

      def rocket_job_processing_schedule
        RocketJob::Plugins::Rufus::CronLine.new(processing_schedule)
      end
    end
  end
end

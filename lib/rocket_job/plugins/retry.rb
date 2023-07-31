require "active_support/concern"

module RocketJob
  module Plugins
    # Automatically retry the job on failure.
    #
    # Example:
    #
    # class MyJob < RocketJob::Job
    #   include RocketJob::Plugins::Retry
    #
    #   # Set the maximum number of times a job should be retried before giving up.
    #   self.retry_limit = 3
    #
    #   def perform
    #     puts "DONE"
    #   end
    # end
    #
    # # Queue the job for processing using the default cron_schedule specified above
    # MyJob.create!
    #
    # # Override the default retry_limit for a specific job instance.
    # MyCronJob.create!(retry_limit: 10)
    #
    # # Disable retries for this job instance.
    # MyCronJob.create!(retry_limit: 0)
    #
    # Below is a table of the delay for each retry attempt, as well as the _total_ duration spent retrying a job for
    # the specified number of retries, excluding actual processing time.
    #
    # |---------|------------|----------------|
    # | Attempt |      Delay | Total Duration |
    # |---------|------------|----------------|
    # |      01 |     6.000s |         6.000s |
    # |      02 |    21.000s |        27.000s |
    # |      03 |     1m 26s |         1m 53s |
    # |      04 |     4m 21s |         6m 14s |
    # |      05 |    10m 30s |        16m 44s |
    # |      06 |    21m 41s |        38m 25s |
    # |      07 |     40m 6s |        20h 18m |
    # |      08 |     20h 8m |        21h 26m |
    # |      09 |    20h 49m |        23h 16m |
    # |      10 |    21h 46m |          2h 3m |
    # |      11 |     23h 4m |          6h 7m |
    # |      12 |     0h 45m |        11h 52m |
    # |      13 |     2h 56m |     1d 19h 48m |
    # |      14 |     5h 40m |      1d 6h 29m |
    # |      15 |      9h 3m |     2d 20h 33m |
    # |      16 |    13h 12m |     2d 14h 45m |
    # |      17 |    18h 12m |     3d 13h 57m |
    # |      18 |   1d 0h 9m |      5d 19h 7m |
    # |      19 |  1d 7h 12m |      6d 7h 19m |
    # |      20 | 1d 15h 26m |      8d 3h 46m |
    # |      21 |   2d 1h 1m |     10d 9h 47m |
    # |      22 |  2d 12h 4m |     13d 2h 51m |
    # |      23 |  3d 0h 44m |     16d 8h 35m |
    # |      24 |  3d 15h 9m |     20d 4h 45m |
    # |      25 |  4d 7h 30m |     24d 17h 16 |
    # |      26 |  5d 1h 56m |     30d 0h 12m |
    # |      27 | 6d 22h 37m |     36d 3h 49m |
    # |      28 | 7d 21h 44m |     43d 6h 34m |
    # |      29 | 8d 23h 28m |     51d 11h 2m |
    # |      30 |   9d 4h 0m |     61d 20h 2m |
    # |---------|------------|----------------|
    module Retry
      extend ActiveSupport::Concern

      included do
        after_fail :rocket_job_retry

        # Maximum number of times to retry this job.
        # The default of 25 is almost 25 days of retries.
        field :retry_limit, type: Integer, default: 25, class_attribute: true, user_editable: true, copy_on_restart: true

        # List of times when this job failed
        field :failed_at_list, type: Array, default: []

        validates_presence_of :retry_limit
      end

      # Returns [true|false] whether this job should be retried on failure.
      def rocket_job_retry_on_fail?
        rocket_job_failure_count < retry_limit
      end

      def rocket_job_failure_count
        failed_at_list.size
      end

      private

      def rocket_job_retry
        # Failure count is incremented during before_fail
        return if expired? || !rocket_job_retry_on_fail?

        delay_seconds = rocket_job_retry_seconds_to_delay
        logger.info "Job failed, automatically retrying in #{delay_seconds} seconds. Retry count: #{failure_count}"

        now         = Time.now
        self.run_at = now + delay_seconds
        failed_at_list << now
        new_record? ? self.retry : retry!
      end

      # Prevent exception from being cleared on retry
      def rocket_job_clear_exception
        self.completed_at = nil
        self.exception    = nil unless rocket_job_retry_on_fail?
        self.worker_name  = nil
      end

      # Returns [Integer] the number of seconds after which to retry this failed job.
      # Uses an exponential back-off algorithm to prevent overloading the failed resource.
      #
      # For example, to see the durations for the first 25 retries:
      #   count = 25
      #   intervals = (1..count).map { |attempt| attempt**4 + 5 }
      #
      # Display the above intervals as human readable durations:
      #   intervals.map { |seconds| RocketJob.seconds_as_duration(seconds) }
      #
      # Then sum the total duration in seconds:
      #   RocketJob.seconds_as_duration(intervals.sum)
      #
      # Or, to see the total durations based on the number of retries:
      #   (0..count).map{|i| "#{i+1} ==> #{RocketJob.seconds_as_duration(intervals[0..i].sum)}"}
      def rocket_job_retry_seconds_to_delay
        rocket_job_failure_count**4 + 5
      end
    end
  end
end

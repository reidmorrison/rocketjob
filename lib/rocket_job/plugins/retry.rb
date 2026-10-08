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
    # the specified number of retries, excluding actual processing time. The delay before retry `n` is
    # `(n - 1)**4 + 5` seconds.
    #
    # |---------|------------|----------------|
    # | Attempt |      Delay | Total Duration |
    # |---------|------------|----------------|
    # |      01 |     5.000s |         5.000s |
    # |      02 |     6.000s |        11.000s |
    # |      03 |    21.000s |        32.000s |
    # |      04 |     1m 26s |         1m 58s |
    # |      05 |     4m 21s |         6m 19s |
    # |      06 |    10m 30s |        16m 49s |
    # |      07 |    21m 41s |        38m 30s |
    # |      08 |     40m 6s |         1h 18m |
    # |      09 |      1h 8m |         2h 26m |
    # |      10 |     1h 49m |         4h 16m |
    # |      11 |     2h 46m |          7h 3m |
    # |      12 |      4h 4m |         11h 7m |
    # |      13 |     5h 45m |        16h 52m |
    # |      14 |     7h 56m |      1d 0h 49m |
    # |      15 |    10h 40m |     1d 11h 29m |
    # |      16 |     14h 3m |      2d 1h 33m |
    # |      17 |    18h 12m |     2d 19h 45m |
    # |      18 |    23h 12m |     3d 18h 57m |
    # |      19 |   1d 5h 9m |       5d 0h 7m |
    # |      20 | 1d 12h 12m |     6d 12h 19m |
    # |      21 | 1d 20h 26m |      8d 8h 46m |
    # |      22 |   2d 6h 1m |    10d 14h 47m |
    # |      23 |  2d 17h 4m |     13d 7h 51m |
    # |      24 |  3d 5h 44m |    16d 13h 36m |
    # |      25 |  3d 20h 9m |     20d 9h 45m |
    # |      26 | 4d 12h 30m |    24d 22h 16m |
    # |      27 |  5d 6h 56m |     30d 5h 12m |
    # |      28 |  6d 3h 37m |     36d 8h 50m |
    # |      29 |  7d 2h 44m |    43d 11h 34m |
    # |      30 |  8d 4h 28m |     51d 16h 2m |
    # |---------|------------|----------------|
    module Retry
      extend ActiveSupport::Concern

      included do
        after_fail :rocket_job_retry

        # Maximum number of times to retry this job.
        # The default of 25 retries spans about 20 days, see the table above.
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
      #   intervals = (0...count).map { |failures| (failures**4) + 5 }
      #
      # Display the above intervals as human readable durations:
      #   intervals.map { |seconds| RocketJob.seconds_as_duration(seconds) }
      #
      # Then sum the total duration in seconds:
      #   RocketJob.seconds_as_duration(intervals.sum)
      #
      # Or, to see the total durations based on the number of retries:
      #   (0...count).map { |i| "#{i + 1} ==> #{RocketJob.seconds_as_duration(intervals[0..i].sum)}" }
      def rocket_job_retry_seconds_to_delay
        (rocket_job_failure_count**4) + 5
      end
    end
  end
end

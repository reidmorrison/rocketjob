require "active_support/concern"

module RocketJob
  module Batch
    # Throttle the number of slices of a specific batch job that are processed at the same time.
    #
    # Example:
    #   class MyJob < RocketJob::Job
    #     include RocketJob::Batch
    #
    #     # Maximum number of slices to process at the same time for each running instance.
    #     self.throttle_running_workers = 25
    #
    #     def perform(record)
    #       # ....
    #     end
    #   end
    #
    # It attempts to ensure that the number of workers do not exceed this number.
    # This is not a hard limit and it is possible for the number of workers to
    # slightly exceed this value at times. It can also occur that the number of
    # slices running can drop below this number for a short period.
    #
    # This value can be modified while a job is running. The change will be picked
    # up at the start of processing slices, or after processing a slice and
    # `re_check_seconds` has been exceeded.
    #
    # 0 or nil : No limits in place
    #
    # Default: nil
    module ThrottleRunningWorkers
      extend ActiveSupport::Concern

      included do
        field :throttle_running_workers, type: Integer, class_attribute: true, user_editable: true, copy_on_restart: true

        validates :throttle_running_workers, numericality: {greater_than_or_equal_to: 0}, allow_nil: true

        define_batch_throttle :throttle_running_workers_exceeded?, filter: :throttle_filter_id
      end

      private

      # Returns [true|false] whether the throttle for this job has been exceeded
      def throttle_running_workers_exceeded?(slice)
        return false unless throttle_running_workers&.positive?

        input.running.with(read: {mode: :primary}) do |conn|
          conn.where(:id.ne => slice.id).count >= throttle_running_workers
        end
      end

      # Allows another job with a higher priority to start even though this one is running already
      # @overrides RocketJob::Plugins::Job::ThrottleRunningJobs#throttle_running_jobs_base_query
      def throttle_running_jobs_base_query
        query                = super
        query[:priority.lte] = priority if throttle_running_workers&.positive?
        query
      end
    end
  end
end

require "active_support/concern"

module RocketJob
  module Batch
    # Throttle the number of slices of a specific batch job that are processed at the same time.
    #
    # Example:
    #   class MyJob < RocketJob
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

        # Deprecated. For backward compatibility.
        alias_method :throttle_running_slices, :throttle_running_workers
        alias_method :throttle_running_slices=, :throttle_running_workers=
      end

      private

      # Returns [Boolean] whether the throttle for this job has been exceeded
      def throttle_running_workers_exceeded?(slice)
        return unless throttle_running_workers&.positive?

        input.running.with(read: {mode: :primary}) do |conn|
          conn.where(:id.ne => slice.id).count >= throttle_running_workers
        end
      end

      # Returns [Boolean] whether the throttle for this job has been exceeded
      #
      # With a Batch job, allow a higher priority queued job to replace a running one with
      # a lower priority.
      def throttle_running_jobs_exceeded?
        return unless throttle_running_jobs&.positive?

        # Cannot use this class since it will include instances of parent job classes.
        RocketJob::Job.with(read: {mode: :primary}) do |conn|
          conn.running.where("_type" => self.class.name, :id.ne => id, :priority.lte => priority).count >= throttle_running_jobs
        end
      end
    end
  end
end

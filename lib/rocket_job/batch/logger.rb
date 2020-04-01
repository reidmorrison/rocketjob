require "active_support/concern"

module RocketJob
  module Batch
    module Logger
      extend ActiveSupport::Concern

      included do
        # Log all state transitions
        after_start :rocket_job_batch_log_state_change
        after_complete :rocket_job_batch_log_state_change
        after_fail :rocket_job_batch_log_state_change
        after_retry :rocket_job_batch_log_state_change
        after_pause :rocket_job_batch_log_state_change
        after_resume :rocket_job_batch_log_state_change
        after_abort :rocket_job_batch_log_state_change
        after_requeue :rocket_job_batch_log_state_change

        around_slice :rocket_job_batch_slice_logger

        # Remove perform level logger and replace with slice level logger
        skip_callback(:perform, :around, :rocket_job_around_logger)
      end

      private

      # Add logging around processing of each slice
      #   - metric allows duration to be forwarded to statsd, etc.
      #   - log_exception logs entire exception if raised
      #   - on_exception_level changes log level from info to error on exception
      #   - silence noisy jobs by raising log level
      def rocket_job_batch_slice_logger(&block)
        logger.measure_info(
          "Completed slice",
          metric:             "#{self.class.name}/slice",
          log_exception:      :full,
          on_exception_level: :error,
          silence:            log_level,
          payload:            {records: rocket_job_slice&.size},
          &block
        )
      end

      def rocket_job_batch_log_state_change
        logger.info(aasm.current_event.to_s.camelcase, rocket_job_batch_log_payload)
      end

      def rocket_job_batch_log_payload
        {
          from:  aasm.from_state,
          to:    aasm.to_state,
          event: aasm.current_event
        }
      end
    end
  end
end

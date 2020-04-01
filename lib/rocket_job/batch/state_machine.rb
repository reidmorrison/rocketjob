require "active_support/concern"

module RocketJob
  module Batch
    # State machine for sliced jobs
    module StateMachine
      extend ActiveSupport::Concern

      included do
        # Replace existing event and all callbacks for that event
        aasm.state_machine.add_event(:retry, {}) do
          # Retry before_batch
          transitions from:  :failed, to: :queued,
                      if:    -> { (sub_state == :before) || sub_state.nil? },
                      after: :rocket_job_requeue_sub_state_before
          # Retry perform and after_batch
          transitions from:  :failed, to: :running,
                      if:    -> { sub_state != :before },
                      after: :rocket_job_requeue_sub_state_after
        end

        # Replace existing event and all callbacks for that event
        aasm.state_machine.add_event(:requeue, {}) do
          # Requeue perform
          transitions from:  :running, to: :running,
                      if:    ->(_server_name) { sub_state == :processing },
                      after: :rocket_job_requeue_sub_state_processing
          # Requeue after_batch
          transitions from:  :running, to: :running,
                      if:    ->(server_name) { worker_on_server?(server_name) && (sub_state == :after) },
                      after: :rocket_job_requeue_sub_state_after
          # Requeue before_batch
          transitions from:  :running, to: :queued,
                      if:    ->(server_name) { worker_on_server?(server_name) && (sub_state == :before) },
                      after: :rocket_job_requeue_sub_state_before
        end

        # Needed again here since the events have been overwritten above
        before_retry :rocket_job_clear_exception

        before_start :rocket_job_sub_state_before
        before_complete :rocket_job_clear_sub_state
        after_abort :cleanup!
        after_retry :rocket_job_requeue_failed_slices
        after_destroy :cleanup!
      end

      # Drop the input and output collections
      def cleanup!
        input_categories.each { |category| input(category).drop }
        output_categories.each { |category| output(category).drop }
      end

      # A batch job can only be processed:
      # - Whilst Queued (before processing).
      # - During processing.
      #
      # I.e. Not during before_batch and after_batch.
      def pausable?
        queued? || paused? || (running? && (sub_state == :processing))
      end

      private

      # Is this job still being processed
      def rocket_job_processing?
        running? && (sub_state == :processing)
      end

      def rocket_job_sub_state_before
        self.sub_state = :before unless sub_state
      end

      def rocket_job_clear_sub_state
        self.sub_state = nil
      end

      # Called after a job in sub_state: :before is requeued
      def rocket_job_requeue_sub_state_before
        self.sub_state   = nil
        self.started_at  = nil
        self.worker_name = nil
      end

      def rocket_job_requeue_sub_state_after
        self.sub_state   = :processing
        self.worker_name = nil
      end

      def rocket_job_requeue_sub_state_processing(worker_name)
        self.worker_name = nil
        input.requeue_running(worker_name)
      end

      # Also retry failed slices when the job itself is re-tried
      def rocket_job_requeue_failed_slices
        input.requeue_failed
      end
    end
  end
end

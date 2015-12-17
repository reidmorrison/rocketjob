# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Concerns
    # State machine for RocketJob::Job
    module JobStateMachine
      extend ActiveSupport::Concern

      included do
        # State Machine events and transitions
        #
        #   :queued -> :running -> :completed
        #                       -> :paused     -> :running
        #                                      -> :aborted
        #                       -> :failed     -> :running
        #                                      -> :aborted
        #                       -> :aborted
        #                       -> :queued (when a worker dies)
        #           -> :aborted
        aasm column: :state do
          # Job has been created and is queued for processing ( Initial state )
          state :queued, initial: true

          # Job is running
          state :running

          # Job has completed processing ( End state )
          state :completed

          # Job is temporarily paused and no further processing will be completed
          # until this job has been resumed
          state :paused

          # Job failed to process and needs to be manually re-tried or aborted
          state :failed

          # Job was aborted and cannot be resumed ( End state )
          state :aborted

          event :start do
            transitions from: :queued, to: :running
          end

          event :complete do
            transitions from: :running, to: :completed
          end

          event :fail do
            transitions from: :queued, to: :failed
            transitions from: :running, to: :failed
            transitions from: :paused, to: :failed
          end

          event :retry do
            transitions from: :failed, to: :queued
          end

          event :pause do
            transitions from: :running, to: :paused
          end

          event :resume do
            transitions from: :paused, to: :running
          end

          event :abort do
            transitions from: :running, to: :aborted
            transitions from: :queued, to: :aborted
            transitions from: :failed, to: :aborted
            transitions from: :paused, to: :aborted
          end

          event :requeue do
            transitions from: :running, to: :queued,
              if:             -> _worker_name { worker_name == _worker_name },
              after:          :clear_started_at
          end
        end
        # @formatter:on

        # Define a before and after callback method for each event
        define_event_callbacks(*aasm.state_machine.events.keys)

        before_start :set_started_at
        before_complete :set_completed_at, :mark_complete
        before_fail :set_completed_at, :increment_failure_count, :set_exception
        before_pause :set_completed_at
        before_abort :set_completed_at
        before_retry :clear_exception
        before_resume :clear_completed_at
      end

      private

      # Sets the exception child object for this job based on the
      # supplied Exception instance or message
      def set_exception(worker_name = nil, exc_or_message = nil)
        if exc_or_message.is_a?(Exception)
          self.exception        = JobException.from_exception(exc_or_message)
          exception.worker_name = worker_name
        else
          build_exception(
            class_name:  'RocketJob::JobException',
            message:     exc_or_message,
            backtrace:   [],
            worker_name: worker_name
          )
        end
      end

      def set_started_at
        self.started_at = Time.now
      end

      def mark_complete
        self.percent_complete = 100
      end

      def increment_failure_count
        self.failure_count += 1
      end

      def clear_exception
        self.completed_at = nil
        self.exception    = nil
        self.worker_name  = nil
      end

      def set_completed_at
        self.completed_at = Time.now
        self.worker_name  = nil
      end

      def clear_completed_at
        self.completed_at = nil
      end

      def clear_started_at
        self.started_at  = nil
        self.worker_name = nil
      end
    end

  end
end


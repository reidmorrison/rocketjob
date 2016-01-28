# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Plugins
    module Job
      # State machine for RocketJob::Job
      module StateMachine
        extend ActiveSupport::Concern

        included do
          # State Machine events and transitions
          #
          #   :queued -> :running -> :completed
          #                       -> :paused     -> :running (if started )
          #                                      -> :queued ( if no started )
          #                                      -> :aborted
          #                       -> :failed     -> :aborted
          #                                      -> :queued
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
              transitions from: :queued, to: :paused
            end

            event :resume do
              transitions from: :paused, to: :running, if: -> { started_at }
              transitions from: :paused, to: :queued, unless: -> { started_at }
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
                after:          :rocket_job_clear_started_at
            end
          end
          # @formatter:on

          # Define a before and after callback method for each event
          state_machine_define_event_callbacks(*aasm.state_machine.events.keys)

          before_start :rocket_job_set_started_at
          before_complete :rocket_job_set_completed_at, :rocket_job_mark_complete
          before_fail :rocket_job_set_completed_at, :rocket_job_increment_failure_count, :rocket_job_set_exception
          before_pause :rocket_job_set_completed_at
          before_abort :rocket_job_set_completed_at
          before_retry :rocket_job_clear_exception
          before_resume :rocket_job_clear_completed_at
          after_complete :rocket_job_destroy_on_complete

          # Pause all running jobs
          def self.pause_all
            running.each(&:pause!)
          end

          # Resume all paused jobs
          def self.resume_all
            paused.each(&:resume!)
          end
        end

        private

        # Sets the exception child object for this job based on the
        # supplied Exception instance or message
        def rocket_job_set_exception(worker_name = nil, exc_or_message = nil)
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

        def rocket_job_set_started_at
          self.started_at = Time.now
        end

        def rocket_job_mark_complete
          self.percent_complete = 100
        end

        def rocket_job_increment_failure_count
          self.failure_count += 1
        end

        def rocket_job_clear_exception
          self.completed_at = nil
          self.exception    = nil
          self.worker_name  = nil
        end

        def rocket_job_set_completed_at
          self.completed_at = Time.now
          self.worker_name  = nil
        end

        def rocket_job_clear_completed_at
          self.completed_at = nil
        end

        def rocket_job_clear_started_at
          self.started_at  = nil
          self.worker_name = nil
        end

        def rocket_job_destroy_on_complete
          destroy if destroy_on_complete && !new_record?
        end
      end

    end
  end
end

# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Concerns
    # Automatically starts a new instance of this job anytime it fails, aborts, or completes
    # Failed jobs are aborted so that they cannot be restarted
    # Include RocketJob::Concerns::Singleton to prevent multiple copies of a job from running at
    # the same time
    #
    # To modify the attributes that are copied across to the model override
    # #initialize_copy
    #
    # Note:
    # - The job will not be restarted if:
    #   - A validation fails after cloning this job.
    #   - The job has expired.
    module Restart
      extend ActiveSupport::Concern

      included do
        after_abort :start_new_instance
        after_complete :start_new_instance
        after_fail :start_new_instance
        before_destroy :start_on_destroy

        aasm column: :state do
          # Abort failed jobs
          event :fail do
            transitions from: :queued, to: :aborted
            transitions from: :running, to: :aborted
            transitions from: :paused, to: :aborted
          end
        end
      end

      # When this job is cloned, set it back to :queued and reset internal
      # variables used when job is run.
      # Notes:
      # - `expires_at` is copied across so that a job keeps restarting until the
      #   expiry is reached, when the job is then permanently destroyed
      # - Any other custom job attributes are also copied to the new job instance
      def initialize_copy(orig)
        super
        self.state         = :queued
        self.created_at    = Time.now
        self.started_at    = nil
        self.completed_at  = nil
        self.failure_count = 0
        self.worker_name   = nil

        self.percent_complete = 0
        self.exception        = nil
        self.result           = nil

        # Copy across run_at if it is in the future
        self.run_at           = nil if run_at && run_at < Time.now
      end

      private

      # Run again in the future, even if this run fails with an exception
      def start_new_instance
        # Must change persisted state before starting a new instance of this job
        save! unless new_record?
        job = clone
        job.save!
        logger.info("Started a new job instance: #{job.id}")
      end

      # Destroy can be called in any state, create a new copy if this one is active
      def start_on_destroy
        start_new_instance if (queued? || running? || paused?) && !expired?
      end

    end
  end
end

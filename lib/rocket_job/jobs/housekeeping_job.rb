module RocketJob
  module Jobs
    # Applies Retention policies to how long jobs are kept.
    #
    # Retentions are specific to each state so that for example completed
    # jobs can be cleaned up before jobs that are running.
    #
    # Only one active instance of this housekeeping job is permitted at a time.
    #
    # Example:
    #   RocketJob::Jobs::HousekeepingJob.create!
    #
    # Example, with the default values that can be modified:
    #   RocketJob::Jobs::HousekeepingJob.create!(
    #     aborted_retention:   7.days,
    #     completed_retention: 7.days,
    #     failed_retention:    14.days,
    #     paused_retention:    nil,
    #     queued_retention:    nil
    #   )
    #
    # Example, overriding defaults and disabling removal of failed jobs:
    #   RocketJob::Jobs::HousekeepingJob.create!(
    #     aborted_retention:   1.day,
    #     completed_retention: 30.minutes,
    #     failed_retention:    nil
    #   )
    class HousekeepingJob < RocketJob::Job
      include RocketJob::Plugins::Cron
      include RocketJob::Plugins::Singleton

      self.priority    = 25
      self.description = "Cleans out historical jobs, and zombie servers."
      # Runs every 15 minutes
      self.cron_schedule = "*/15 * * * * UTC"

      # Whether to destroy zombie servers automatically
      field :destroy_zombies, type: Boolean, default: true, user_editable: true, copy_on_restart: true

      # Retention intervals in seconds.
      # Set to nil to retain everything.
      field :aborted_retention, type: Integer, default: 7.days, user_editable: true, copy_on_restart: true
      field :completed_retention, type: Integer, default: 7.days, user_editable: true, copy_on_restart: true
      field :failed_retention, type: Integer, default: 14.days, user_editable: true, copy_on_restart: true
      field :paused_retention, type: Integer, user_editable: true, copy_on_restart: true
      field :queued_retention, type: Integer, user_editable: true, copy_on_restart: true

      def perform
        RocketJob::Job.aborted.where(completed_at: {"$lte" => aborted_retention.seconds.ago}).destroy_all if aborted_retention
        if completed_retention
          RocketJob::Job.completed.where(completed_at: {"$lte" => completed_retention.seconds.ago}).destroy_all
        end
        RocketJob::Job.failed.where(completed_at: {"$lte" => failed_retention.seconds.ago}).destroy_all if failed_retention
        RocketJob::Job.paused.where(completed_at: {"$lte" => paused_retention.seconds.ago}).destroy_all if paused_retention
        RocketJob::Job.queued.where(created_at: {"$lte" => queued_retention.seconds.ago}).destroy_all if queued_retention

        if destroy_zombies
          # Cleanup zombie servers
          RocketJob::Server.destroy_zombies
          # Requeue jobs where the worker is in the zombie state and its server has gone away
          RocketJob::ActiveWorker.requeue_zombies
        end
      end
    end
  end
end

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

      self.priority      = 25
      self.description   = 'Cleans out historical jobs'
      # Runs hourly on the hour
      self.cron_schedule = '0 * * * * America/New_York'

      # Retention intervals in seconds
      # Set to nil to not
      field :aborted_retention, type: Integer, default: 7.days
      field :completed_retention, type: Integer, default: 7.days
      field :failed_retention, type: Integer, default: 14.days
      field :paused_retention, type: Integer
      field :queued_retention, type: Integer

      def perform
        RocketJob::Job.aborted.where(created_at: {'$lte' => aborted_retention.seconds.ago}).destroy_all if aborted_retention
        RocketJob::Job.completed.where(created_at: {'$lte' => completed_retention.seconds.ago}).destroy_all if completed_retention
        RocketJob::Job.failed.where(created_at: {'$lte' => failed_retention.seconds.ago}).destroy_all if failed_retention
        RocketJob::Job.paused.where(created_at: {'$lte' => paused_retention.seconds.ago}).destroy_all if paused_retention
        RocketJob::Job.queued.where(created_at: {'$lte' => queued_retention.seconds.ago}).destroy_all if queued_retention
      end

    end
  end
end

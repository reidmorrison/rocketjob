# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Concerns
    # Automatically schedules the job to start based on the supplied `cron_schedule`.
    # Once started the job will automatically restart on completion and will only run again
    # according to the `cron_schedule`.
    # Failed jobs are aborted so that they cannot be restarted since a new instance has already
    # been enqueued.
    #
    # Include RocketJob::Concerns::Singleton to prevent multiple copies of the job from running at
    # the same time.
    #
    # Note:
    # - The job will not be restarted if:
    #   - A validation fails after cloning this job.
    #   - The job has expired.
    #
    # Example:
    #
    # class MyCronJob < RocketJob::Job
    #   include RocketJob::Concerns::Cron
    #
    #   # Set the default cron_schedule
    #   rocket_job do |job|
    #     job.cron_schedule = "* 1 * * * UTC"
    #   end
    #
    #   def perform
    #     puts "DONE"
    #   end
    # end
    #
    # # Queue the job for processing using the default cron_schedule specified above
    # MyCronJob.create!
    #
    # # Set the cron schedule:
    # MyCronJob.create!(cron_schedule: '* 1 * * * America/New_York')
    #
    #
    # Note:
    #
    # To prevent multiple instances of the job from running at the same time,
    # add: "include RocketJob::Concerns::Singleton"
    #
    # Example: Only allow one instance of the cron job to run at a time:
    #
    # class MyCronJob < RocketJob::Job
    #   # Add `cron_schedule`
    #   include RocketJob::Concerns::Cron
    #   # Prevents mutiple instances from being queued or run at the same time
    #   include RocketJob::Concerns::Singleton
    #
    #   # Set the default cron_schedule
    #   rocket_job do |job|
    #     job.cron_schedule = "* 1 * * * UTC"
    #   end
    #
    #   def perform
    #     puts "DONE"
    #   end
    # end
    #
    module Cron
      extend ActiveSupport::Concern

      included do
        include Restart

        key :cron_schedule, String

        before_create :rocket_job_set_run_at

        validates_presence_of :cron_schedule
        validates_each :cron_schedule do |record, attr, value|
          begin
            Rufus::Scheduler::CronLine.new(value)
          rescue ArgumentError => exc
            record.errors.add(attr, exc.message)
          end
        end
      end

      private

      def rocket_job_set_run_at
        self.run_at = Rufus::Scheduler::CronLine.new(cron_schedule).next_time
      end

    end
  end
end

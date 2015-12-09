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

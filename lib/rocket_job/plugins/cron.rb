require 'active_support/concern'

module RocketJob
  module Plugins
    # Automatically schedules the job to start based on the supplied `cron_schedule`.
    # Once started the job will automatically restart on completion and will only run again
    # according to the `cron_schedule`.
    # Failed jobs are aborted so that they cannot be restarted since a new instance has already
    # been enqueued.
    #
    # Include RocketJob::Plugins::Singleton to prevent multiple copies of the job from running at
    # the same time.
    #
    # Unlike cron, if a job is already running, another one is not queued when the cron
    # schedule needs another started, but rather on completion of the current job. This prevents
    # multiple instances of the same job from running at the same time. The next instance of the
    # job is only scheduled on completion of the current job instance.
    #
    # For example if the job takes 10 minutes to complete, and is scheduled to run every 5 minutes,
    # it will only be run every 10 minutes.
    #
    # Their is no centralized scheduler or need to start schedulers anywhere, since the jobs
    # can be picked up by any Rocket Job worker. Once processing is complete a new instance is then
    # automatically scheduled based on the `cron_schedule`.
    #
    # A job is only queued to run at the specified `cron_schedule`, it will only run if there are workers
    # available to run. For example if workers are busy working on higher priority jobs, then the job
    # will only run once those jobs have completed, or their priority lowered. Additionally, while the
    # job is queued no additional instances will be enqueued, even if the next cron interval has been reached.
    #
    # Note:
    # - The job will not be restarted if:
    #   - A validation fails after cloning this job.
    #   - The job has expired.
    #
    # Example:
    #
    # class MyCronJob < RocketJob::Job
    #   include RocketJob::Plugins::Cron
    #
    #   # Set the default cron_schedule
    #   self.cron_schedule = "* 1 * * * UTC"
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
    # add: "include RocketJob::Plugins::Singleton"
    #
    # Example: Only allow one instance of the cron job to run at a time:
    #
    # class MyCronJob < RocketJob::Job
    #   # Add `cron_schedule`
    #   include RocketJob::Plugins::Cron
    #   # Prevents mutiple instances from being queued or run at the same time
    #   include RocketJob::Plugins::Singleton
    #
    #   # Set the default cron_schedule
    #   self.cron_schedule = "* 1 * * * UTC"
    #
    #   def perform
    #     puts "DONE"
    #   end
    # end
    #
    # Note: The cron_schedule field is formatted as follows:
    #
    #     *    *    *    *    *    *
    #     ┬    ┬    ┬    ┬    ┬    ┬
    #     │    │    │    │    │    │
    #     │    │    │    │    │    └ Optional: Timezone, for example: 'America/New_York', 'UTC'
    #     │    │    │    │    └───── day_of_week (0-7) (0 or 7 is Sun, or use 3-letter names)
    #     │    │    │    └────────── month (1-12, or use 3-letter names)
    #     │    │    └─────────────── day_of_month (1-31)
    #     │    └──────────────────── hour (0-23)
    #     └───────────────────────── minute (0-59)
    #
    # * When specifying day of week, both day 0 and day 7 is Sunday.
    # * Ranges & Lists of numbers are allowed.
    # * Ranges or lists of names are not allowed.
    # * Ranges can include 'steps', so `1-9/2` is the same as `1,3,5,7,9`.
    # * Months or days of the week can be specified by name.
    # * Use the first three letters of the particular day or month (case doesn't matter).
    # * The timezone is recommended to prevent any issues with possible default timezone
    #   differences across servers, or environments.
    module Cron
      extend ActiveSupport::Concern

      included do
        include Restart

        field :cron_schedule, type: String, class_attribute: true, user_editable: true, copy_on_restart: true

        before_create :rocket_job_set_run_at

        validates_presence_of :cron_schedule
        validates_each :cron_schedule do |record, attr, value|
          begin
            RocketJob::Plugins::Rufus::CronLine.new(value)
          rescue ArgumentError => exc
            record.errors.add(attr, exc.message)
          end
        end
      end

      private

      def rocket_job_set_run_at
        self.run_at = RocketJob::Plugins::Rufus::CronLine.new(cron_schedule).next_time
      end

    end
  end
end

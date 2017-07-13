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
    # Notes:
    # - The job will not be restarted if:
    #   - A validation fails after cloning this job.
    #   - The job has expired.
    # - Any time the `cron_schedule` is changed, the `run_at` is automatically set before saving the changes.
    #   - However, if the `run_at` is explicitly set then it will not be overridden.
    # - `cron_schedule` is not a required field so that the same job class
    #   - can be scheduled to run at regular intervals,
    #   - and run on an ad-hoc basis with custom values.
    # - On job failure
    #   - a new future instance is created immediately.
    #   - the current instance is marked as failed and its cron schedule is set to nil.
    #     - Prevents the failed instance from creating a new future instance when it completes.
    #
    # Example, schedule the job to run at regular intervals:
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
    # # Queue the job for processing using the default cron_schedule specified above.
    # MyCronJob.create!
    #
    #
    # Example, a job that can run at regular intervals, and can be run for ad-hoc reporting etc.:
    #
    # class ReportJob < RocketJob::Job
    #   # Do not set a default cron_schedule so that the job can also be used for ad-hoc work.
    #   include RocketJob::Plugins::Cron
    #
    #   field :start_date, type: Date
    #   field :end_date,   type: Date
    #
    #   def perform
    #     # Uses `scheduled_at` to take into account any possible delays.
    #     self.start_at ||= scheduled_at.beginning_of_week.to_date
    #     self.end_at   ||= scheduled_at.end_of_week.to_date
    #
    #     puts "Running report, starting at #{start_date}, ending at #{end_date}"
    #   end
    # end
    #
    # # Queue the job for processing using a cron_schedule.
    # # On completion the job will create a new instance to run at a future date.
    # ReportJob.create!(cron_schedule: '* 1 * * * America/New_York')
    #
    # # Queue the job for processing outside of the above cron schedule.
    # # On completion the job will _not_ create a new instance to run at a future date.
    # job = ReportJob.create!(start_date: 30.days.ago, end_date: 10.days.ago)
    #
    #
    # To prevent multiple instances of the job from running at the same time, add the singleton plug-in:
    #   include RocketJob::Plugins::Singleton
    #
    # Example: Only allow one instance of this job to be active at the same time (running, queued, scheduled, or failed):
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

        before_save :rocket_job_set_run_at

        validates_each :cron_schedule do |record, attr, value|
          begin
            RocketJob::Plugins::Rufus::CronLine.new(value) if value
          rescue ArgumentError => exc
            record.errors.add(attr, exc.message)
          end
        end

        private

        # Prevent auto restart if this job does not have a cron schedule.
        # Overrides: RocketJob::Plugins::Restart#rocket_job_restart_new_instance
        def rocket_job_restart_new_instance
          return unless cron_schedule
          super
        end

        # On failure:
        # - create a new instance scheduled to run in the future.
        # - clear out the `cron_schedule` so this instance will not schedule another instance to run on completion.
        # Overrides: RocketJob::Plugins::Restart#rocket_job_restart_abort
        def rocket_job_restart_abort
          return unless cron_schedule
          rocket_job_restart_new_instance
          self.cron_schedule = nil
        end
      end

      # Returns [Time] at which this job was intended to run at.
      #
      # Takes into account any delays that could occur.
      # Recommended to use this Time instead of Time.now in the `#perform` since the job could run outside its
      # intended window. Especially if a failed job is only retried quite sometime later.
      #
      # Notes:
      # * When `cron_schedule` is set, this would be the `run_at` time, otherwise it is the `created_at` time
      #   since that would be the intended time for which this job is running.
      def scheduled_at
        run_at || created_at
      end

      # Returns [Time] the next time this job will be scheduled to run at.
      #
      # Parameters
      #   time: [Time]
      #     The next time as of this time.
      #     Default: Time.now
      def rocket_job_cron_next_time(time = Time.now)
        RocketJob::Plugins::Rufus::CronLine.new(cron_schedule).next_time(time)
      end

      private

      def rocket_job_set_run_at
        return unless cron_schedule
        self.run_at = rocket_job_cron_next_time if cron_schedule_changed? && !run_at_changed?
      end

    end
  end
end

require 'active_support/concern'

module RocketJob
  module Plugins
    # Schedule jobs to run at set intervals.
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
          update_attribute(:cron_schedule, nil)
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

      # Make this job run now, regardless of the cron schedule.
      # Upon completion the job will automatically reschedule itself.
      def run_now!
        update_attributes(run_at: nil) if cron_schedule
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

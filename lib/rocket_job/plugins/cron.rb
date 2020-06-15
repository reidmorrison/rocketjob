require "active_support/concern"
require "fugit"

module RocketJob
  module Plugins
    # Allow jobs to run on a predefined schedule, much like a crontab.
    #
    # Notes:
    # - No single point of failure since their is no centralized scheduler.
    # - `cron_schedule` can be edited at any time via the web interface.
    # - A scheduled job can be run at any time by calling `#run_now!` or
    #   by clicking `Run Now` in the web interface.
    module Cron
      extend ActiveSupport::Concern

      included do
        include Restart

        field :cron_schedule, type: String, class_attribute: true, user_editable: true, copy_on_restart: true

        validates_each :cron_schedule do |record, attr, value|
          record.errors.add(attr, "Invalid cron_schedule: #{value.inspect}") if value && !Fugit::Cron.new(value)
        end
        before_save :rocket_job_cron_set_run_at

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

      # Returns [Time] the next time this job will be scheduled to run at.
      #
      # Parameters
      #   time: [Time]
      #     The next time as of this time.
      #     Default: Time.now
      def rocket_job_cron_next_time(time = Time.now)
        Fugit::Cron.new(cron_schedule).next_time.to_utc_time
      end

      def rocket_job_cron_set_run_at
        return unless cron_schedule

        self.run_at = rocket_job_cron_next_time if cron_schedule_changed? && !run_at_changed?
      end
    end
  end
end

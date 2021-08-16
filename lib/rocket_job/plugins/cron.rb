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
        field :cron_schedule, type: String, class_attribute: true, user_editable: true, copy_on_restart: true

        # Whether to prevent another instance of this job from running with the exact _same_ cron schedule.
        # Another job instance with a different `cron_schedule` string is permitted.
        field :cron_singleton, type: Mongoid::Boolean, default: true, class_attribute: true, user_editable: true, copy_on_restart: true

        # Whether to re-schedule the next job occurrence when this job starts, or when it is complete.
        #
        # `true`: Create a new scheduled instance of this job after it has started. (Default)
        #   - Ensures that the next scheduled instance is not missed because the current instance is still running.
        #   - Any changes to fields marked with `copy_on_restart` of `true` will be saved to the new scheduled instance
        #     _only_ if they were changed during an `after_start` callback.
        #     Changes to these during other callbacks or during the `perform` will not be saved to the new scheduled
        #     instance.
        #   - To prevent this job creating any new duplicate instances during subsequent processing,
        #     its `cron_schedule` is set to `nil`.
        #
        # `false`: Create a new scheduled instance of this job on `fail`, or `abort`.
        #   - Prevents the next scheduled instance from running or being scheduled while the current instance is
        #     still running.
        #   - Any changes to fields marked with `copy_on_restart` of `true` will be saved to the new scheduled instance
        #     at any time until after the job has failed, or is aborted.
        #   - To prevent this job creating any new duplicate instances during subsequent processing,
        #     its `cron_schedule` is set to `nil` after it fails or is aborted.
        field :cron_after_start, type: Mongoid::Boolean, default: true, class_attribute: true, user_editable: true, copy_on_restart: true

        validates_each :cron_schedule do |record, attr, value|
          record.errors.add(attr, "Invalid cron_schedule: #{value.inspect}") if value && !Fugit::Cron.new(value)
        end
        validate :rocket_job_cron_singleton_check

        before_save :rocket_job_cron_set_run_at

        after_start :rocket_job_cron_on_start
        after_abort :rocket_job_cron_end_state
        after_complete :rocket_job_cron_end_state
        after_fail :rocket_job_cron_end_state
      end

      def rocket_job_cron_set_run_at
        return if cron_schedule.nil? || !(cron_schedule_changed? && !run_at_changed?)

        self.run_at = Fugit::Cron.new(cron_schedule).next_time.to_utc_time
      end

      private

      def rocket_job_cron_on_start
        return unless cron_schedule && cron_after_start

        current_cron_schedule = cron_schedule
        update_attribute(:cron_schedule, nil)
        create_restart!(cron_schedule: current_cron_schedule)
      end

      def rocket_job_cron_end_state
        return unless cron_schedule && !cron_after_start

        current_cron_schedule = cron_schedule
        update_attribute(:cron_schedule, nil)
        create_restart!(cron_schedule: current_cron_schedule)
      end

      # Returns [true|false] whether another instance of this job with the same cron schedule is already active
      def rocket_job_cron_duplicate?
        self.class.with(read: {mode: :primary}) do |conn|
          conn.where(:state.in => %i[queued running failed paused], :id.ne => id, cron_schedule: cron_schedule).exists?
        end
      end

      # Prevent creation of a new job when another is running with the same cron schedule.
      def rocket_job_cron_singleton_check
        return if cron_schedule.nil? || completed? || aborted? || !rocket_job_cron_duplicate?

        errors.add(:state, "Another instance of #{self.class.name} is already queued, running, failed, or paused with the same cron schedule: #{cron_schedule}")
      end
    end
  end
end

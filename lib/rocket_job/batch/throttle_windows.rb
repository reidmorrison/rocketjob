require "active_support/concern"
require "fugit"

module RocketJob
  module Batch
    # For a batch job that can run over a long period of time it can be useful
    # to prevent its slices from being processed outside a predefined processing window.
    #
    # This plugin supports up to 2 different processing windows.
    #
    # For example, do not run this job during business hours.
    # Allow it to run from 5pm until 8am the following day Mon through Fri.
    #
    #   class AfterHoursJob < RocketJob::Job
    #     include RocketJob::Batch
    #     include RocketJob::Batch::ThrottleWindows
    #
    #     # Monday through Thursday the job can start processing at 5pm Eastern.
    #     self.primary_schedule = "0 17 * * 1-4 America/New_York"
    #     # Slices are allowed to run until 8am the following day, which is 15 hours long:
    #     self.primary_duration = 15.hours
    #
    #     # The slices for this job can run all weekend long, starting Friday at 5pm Eastern.
    #     self.secondary_schedule = "0 17 * * 5 America/New_York"
    #     # Slices are allowed to run until 8am on Monday morning, which is 63 hours long:
    #     self.secondary_duration = 63.hours
    #   end
    #
    # Notes:
    # * These schedules do not affect when the job is started, completed, or when `before_batch` or
    #   `after_batch` processing is performed. It only limits when individual slices are processed.
    module ThrottleWindows
      extend ActiveSupport::Concern

      included do
        # Beginning of the primary schedule. In cron format, see Scheduled Jobs `cron_schedule` for examples.
        field :primary_schedule, type: String, class_attribute: true, user_editable: true, copy_on_restart: true
        # Duration in seconds of the primary window.
        field :primary_duration, type: Integer, class_attribute: true, user_editable: true, copy_on_restart: true

        # Beginning of the secondary schedule. In cron format, see Scheduled Jobs `cron_schedule` for examples.
        field :secondary_schedule, type: String, class_attribute: true, user_editable: true, copy_on_restart: true
        # Duration in seconds of the secondary window.
        field :secondary_duration, type: Integer, class_attribute: true, user_editable: true, copy_on_restart: true

        define_batch_throttle :throttle_windows_exceeded?, filter: :throttle_filter_id

        validates_each :primary_schedule, :secondary_schedule do |record, attr, value|
          record.errors.add(attr, "Invalid #{attr}: #{value.inspect}") if value && !Fugit::Cron.new(value)
        end
      end

      private

      def throttle_windows_exceeded?
        exceeded = primary_schedule && primary_duration && throttle_outside_window?(primary_schedule, primary_duration)
        if exceeded && secondary_schedule && secondary_duration
          exceeded = throttle_outside_window?(secondary_schedule, secondary_duration)
        end
        exceeded
      end

      def throttle_outside_window?(schedule, duration)
        cron = Fugit::Cron.new(schedule)
        time = Time.now.utc + 1
        # Add 1 second since right now could be the very beginning of the processing window.
        previous_time = cron.previous_time(time).to_utc_time
        previous_time + duration < time
      end
    end
  end
end

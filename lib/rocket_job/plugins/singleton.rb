require 'active_support/concern'

module RocketJob
  module Plugins
    # Prevent this job from being saved if another is running, queued, or paused.
    module Singleton
      extend ActiveSupport::Concern

      included do
        validate :rocket_job_singleton_check
      end

      # Returns [true|false] whether another instance of this job is already active
      def rocket_job_singleton_active?
        self.class.with(read: {mode: :primary}) do |conn|
          conn.where(:state.in => %i[running queued], :id.ne => id).exists?
        end
      end

      private

      # Validation prevents a new job from being saved while one is already running
      def rocket_job_singleton_check
        return unless (running? || queued? || paused?) && rocket_job_singleton_active?

        errors.add(:state, "Another instance of #{self.class.name} is already running, queued, or paused")
      end

    end
  end
end

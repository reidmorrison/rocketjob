# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Plugins
    # Prevent more than one instance of this job class from running at a time
    module Singleton
      extend ActiveSupport::Concern

      included do
        # Validation prevents a new job from being saved while one is already running
        validates_each :state do |record, attr, value|
          if (record.running? || record.queued? || record.paused?) && record.rocket_job_singleton_active?
            record.errors.add(attr, "Another instance of #{record.class.name} is already queued or running")
          end
        end

        # Returns [true|false] whether another instance of this job is already active
        def rocket_job_singleton_active?
          self.class.where(:state.in => [:running, :queued], :id.ne => id).exists?
        end
      end

    end
  end
end

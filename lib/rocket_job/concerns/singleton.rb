# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Concerns
    # Prevent more than one instance of this job class from running at a time
    module Singleton
      extend ActiveSupport::Concern

      included do
        # Validation prevents a new job from being saved while one is already running
        validates_each :state do |record, attr, value|
          if (record.running? || record.queued? || record.paused?) && record.singleton_job_active?
            record.errors.add(attr, "Another instance of #{record.class.name} is already queued or running")
          end
        end

        # Returns [true|false] whether another instance of this job is already active
        def singleton_job_active?
          self.class.where(state: [:running, :queued], _id: {'$ne' => id}).exists?
        end
      end

    end
  end
end

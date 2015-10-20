# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Concerns
    # Prevent more than one instance of this job class from running at a time
    module Singleton
      extend ActiveSupport::Concern

      included do
        validates_each :state do |record, attr, value|
          if (record.queued? || record.running?) && where(state: [:running, :queued], _id: {'$ne' => record.id}).exists?
            record.errors.add(attr, 'Another instance of this job is already queued or running')
          end
        end

        after_fail :start_new_instance
        after_abort :start_new_instance
        after_complete :start_new_instance
      end

      # Run again in the future, even if this run fails with an exception
      def start_new_instance
        save! unless new_record?
        # Validation will prevent duplicates from starting
        self.class.create(
          previous_file_names: previous_file_names,
          priority:            priority,
          check_seconds:       check_seconds,
          run_at:              Time.now + check_seconds
        )
      end

    end
  end
end

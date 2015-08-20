# encoding: UTF-8
require 'active_support/concern'

# Worker behavior for a job
module RocketJob
  module Concerns
    module Singleton
      extend ActiveSupport::Concern

      included do
        # Start the single instance of this job
        #
        # Returns true if the job was started
        # Returns false if the job is already running and doe not need to be started
        def self.start(*args, &block)
          # Prevent multiple Jobs of the same class from running at the same time
          return false if where(state: [:running, :queued]).count > 0

          perform_later(*args, &block)
          true
        end

        # TODO Make :perform_later, :perform_now, :perform, :now protected/private
        #      class << self
        #        # Ensure that only one instance of the job is running.
        #        protected :perform_later, :perform_now, :perform, :now
        #      end
        #self.send(:protected, :perform_later)

      end
    end
  end
end

require "active_support/concern"

module RocketJob
  module Plugins
    # @deprecated
    module Restart
      extend ActiveSupport::Concern

      included do
        after_abort :create_restart!
        after_complete :create_restart!
        after_fail :rocket_job_restart_abort
      end

      private

      def rocket_job_restart_abort
        new_record? ? abort : abort!
      end
    end
  end
end

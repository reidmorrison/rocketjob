# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Concerns
    # Allow each child job to set its own defaults
    module Defaults
      extend ActiveSupport::Concern

      included do
        # Copy parent job defaults
        def self.inherited(base)
          super
          @rocket_job_defaults.each { |block| base.rocket_job(&block) } if @rocket_job_defaults
        end

        # Override parent defaults
        def self.rocket_job(&block)
          (@rocket_job_defaults ||=[]) << block
        end

        private

        def self.rocket_job_defaults
          @rocket_job_defaults
        end

        # Apply defaults after creating the model but before applying values
        def rocket_job_set_defaults
          if defaults = self.class.rocket_job_defaults
            defaults.each { |block| block.call(self) }
          end
        end
      end

    end
  end
end

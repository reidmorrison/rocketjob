# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Plugins
    module Job
      module Logger
        extend ActiveSupport::Concern

        included do
          around_perform :rocket_job_around_logger
        end

        private

        # Add logging around the perform call
        #   - metric allows duration to be forwarded to statsd, etc.
        #   - log_exception logs entire exception if raised
        #   - on_exception_level changes log level from info to error on exception
        #   - silence noisy jobs by raising log level
        def rocket_job_around_logger(&block)
          logger.info('Start #perform')
          logger.benchmark_info(
            'Completed #perform',
            metric:             "rocketjob/#{self.class.name.underscore}",
            log_exception:      :full,
            on_exception_level: :error,
            silence:            log_level,
            &block
          )
        end

      end
    end
  end
end

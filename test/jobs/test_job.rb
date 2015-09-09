require 'rocketjob'
module Jobs
  class TestJob < RocketJob::Job
    rocket_job do |job|
      job.priority = 51
    end

    @@result = nil

    # For holding test results
    def self.result
      @@result
    end

    def perform(first)
      @@result = first + 1
    end

    def sum(a, b)
      @@result = a + b
    end

    # Test silencing noisy logging
    def noisy_logger
      logger.info 'some very noisy logging'
    end

    # Test increasing log level for debugging purposes
    def debug_logging
      logger.trace 'enable tracing level for just the job instance'
    end

    def before_event(hash)
      hash['before_event'] = true
    end

    def event(hash)
      hash['event'] = true
    end

    def after_event(hash)
      hash['after_event'] = true
    end

  end
end

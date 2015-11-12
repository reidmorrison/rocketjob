require 'rocketjob'
module Jobs
  class NoisyJob < RocketJob::Job
    rocket_job do |job|
      job.priority = 51
    end

    # Test silencing noisy logging
    def perform
      logger.info 'some very noisy logging'
    end

  end
end

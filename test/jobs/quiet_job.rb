require 'rocketjob'
module Jobs
  class QuietJob < RocketJob::Job
    rocket_job do |job|
      job.priority = 51
    end

    # Test increasing log level for debugging purposes
    def perform
      logger.trace 'enable tracing level for just the job instance'
    end

  end
end

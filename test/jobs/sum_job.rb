require 'rocketjob'
module Jobs
  class SumJob < RocketJob::Job
    rocket_job do |job|
      job.priority = 51
    end

    @@result = nil

    # For temp test data
    def self.result
      @@result
    end

    def perform(a, b)
      @@result = a + b
    end

  end
end

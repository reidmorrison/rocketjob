require 'rocketjob'
module Jobs
  class HashJob < RocketJob::Job
    rocket_job do |job|
      job.priority = 51
    end

    def perform(hash)
      hash
    end

  end
end

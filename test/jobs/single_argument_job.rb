require 'rocketjob'
module Jobs
  class SingleArgumentJob < RocketJob::Job
    rocket_job do |job|
      job.priority = 51
    end

    def perform(value)
      value
    end

  end
end

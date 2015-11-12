require 'rocketjob'
module Jobs
  class EventJob < RocketJob::Job
    rocket_job do |job|
      job.priority = 51
    end

    #
    # New style callbacks
    #
    before_perform do
      arguments.first['before_event'] = 1
      # Change jobs priority
      self.priority = 27
    end

    # Second before event that must be run first since it is defined last
    # If run in the wrong order will result in 'nil does not understand +='
    before_perform do
      arguments.first['before_event'] += 1
    end

    around_perform do |job, block|
      # After all the before callbacks
      job.arguments.first['before_event'] += 1
      block.call
      # Last after callback
      job.arguments.first['after_event'] += 1
    end

    def event(hash)
      3645
    end

    # Second after event that must be run second since it is after the one above
    # If run in the wrong order will result in 'nil does not understand +='
    after_perform do
      arguments.first['after_event'] += 1
    end

    # First after callback since called in reverse order
    after_perform do
      arguments.first['after_event'] = 1
    end

  end
end

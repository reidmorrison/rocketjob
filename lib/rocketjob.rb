# encoding: UTF-8
require 'mongo'
require 'mongo_ha'
require 'mongo_mapper'
require 'semantic_logger'
require 'rocket_job/version'

# @formatter:off
module RocketJob
  autoload :CLI,              'rocket_job/cli'
  autoload :Config,           'rocket_job/config'
  autoload :DirmonEntry,      'rocket_job/dirmon_entry'
  autoload :Heartbeat,        'rocket_job/heartbeat'
  autoload :Job,              'rocket_job/job'
  autoload :JobException,     'rocket_job/job_exception'
  autoload :Worker,           'rocket_job/worker'
  module Concerns
    autoload :Callbacks,      'rocket_job/concerns/callbacks'
    autoload :EventCallbacks, 'rocket_job/concerns/event_callbacks'
    autoload :Worker,         'rocket_job/concerns/worker'
    autoload :Singleton,      'rocket_job/concerns/singleton'
    autoload :StateMachine,   'rocket_job/concerns/state_machine'
  end
  module Jobs
    autoload :DirmonJob,      'rocket_job/jobs/dirmon_job'
  end

  # @formatter:on
  # Returns a human readable duration from the supplied [Float] number of seconds
  def self.seconds_as_duration(seconds)
    time = Time.at(seconds)
    if seconds >= 1.day
      "#{(seconds / 1.day).to_i}d #{time.strftime('%-Hh %-Mm %-Ss')}"
    elsif seconds >= 1.hour
      time.strftime('%-Hh %-Mm %-Ss')
    elsif seconds >= 1.minute
      time.strftime('%-Mm %-Ss')
    else
      time.strftime('%-Ss')
    end
  end
end

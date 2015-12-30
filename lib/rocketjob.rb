# encoding: UTF-8
require 'semantic_logger'
require 'rocket_job/extensions/mongo'
require 'rocket_job/extensions/rufus_scheduler'
require 'mongo_ha'
require 'mongo_mapper'
require 'rocket_job/version'

# @formatter:off
module RocketJob
  autoload :CLI,               'rocket_job/cli'
  autoload :Config,            'rocket_job/config'
  autoload :DirmonEntry,       'rocket_job/dirmon_entry'
  autoload :Heartbeat,         'rocket_job/heartbeat'
  autoload :Job,               'rocket_job/job'
  autoload :JobException,      'rocket_job/job_exception'
  autoload :Worker,            'rocket_job/worker'

  module Concerns
    autoload :Callbacks,       'rocket_job/concerns/callbacks'
    autoload :Cron,            'rocket_job/concerns/cron'
    autoload :Defaults,        'rocket_job/concerns/defaults'
    autoload :Document,        'rocket_job/concerns/document'
    autoload :EventCallbacks,  'rocket_job/concerns/event_callbacks'
    autoload :JobStateMachine, 'rocket_job/concerns/job_state_machine'
    autoload :Logger,          'rocket_job/concerns/logger'
    autoload :Model,           'rocket_job/concerns/model'
    autoload :Persistence,     'rocket_job/concerns/persistence'
    autoload :Restart,         'rocket_job/concerns/restart'
    autoload :Singleton,       'rocket_job/concerns/singleton'
    autoload :StateMachine,    'rocket_job/concerns/state_machine'
    autoload :Worker,          'rocket_job/concerns/worker'
  end

  module Jobs
    autoload :DirmonJob,       'rocket_job/jobs/dirmon_job'
    autoload :SimpleJob,       'rocket_job/jobs/simple_job'
  end

  # @formatter:on
  # Returns a human readable duration from the supplied [Float] number of seconds
  def self.seconds_as_duration(seconds)
    return nil unless seconds
    if seconds >= 86400.0 # 1 day
      "#{(seconds / 86400).to_i}d #{Time.at(seconds).strftime('%-Hh %-Mm')}"
    elsif seconds >= 3600.0 # 1 hour
      Time.at(seconds).strftime('%-Hh %-Mm')
    elsif seconds >= 60.0 # 1 minute
      Time.at(seconds).strftime('%-Mm %-Ss')
    elsif seconds >= 1.0 # 1 second
      "#{'%.3f' % seconds}s"
    else
      duration = seconds * 1000
      if defined? JRuby
        "#{duration.to_i}ms"
      else
        duration < 10.0 ? "#{'%.3f' % duration}ms" : "#{'%.1f' % duration}ms"
      end
    end
  end

end

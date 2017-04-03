require 'semantic_logger'
require 'mongoid'
require 'rocket_job/extensions/mongo/logging'
require 'rocket_job/version'
require 'rocket_job/rocket_job'

# @formatter:off
module RocketJob
  autoload :ActiveWorker,       'rocket_job/active_worker'
  autoload :CLI,                'rocket_job/cli'
  autoload :Config,             'rocket_job/config'
  autoload :DirmonEntry,        'rocket_job/dirmon_entry'
  autoload :Heartbeat,          'rocket_job/heartbeat'
  autoload :Job,                'rocket_job/job'
  autoload :JobException,       'rocket_job/job_exception'
  autoload :Worker,             'rocket_job/worker'
  autoload :Performance,        'rocket_job/performance'
  autoload :Server,             'rocket_job/server'

  module Plugins
    module Job
      autoload :Callbacks,           'rocket_job/plugins/job/callbacks'
      autoload :Defaults,            'rocket_job/plugins/job/defaults'
      autoload :StateMachine,        'rocket_job/plugins/job/state_machine'
      autoload :Logger,              'rocket_job/plugins/job/logger'
      autoload :Model,               'rocket_job/plugins/job/model'
      autoload :Persistence,         'rocket_job/plugins/job/persistence'
      autoload :Throttle,            'rocket_job/plugins/job/throttle'
      autoload :ThrottleRunningJobs, 'rocket_job/plugins/job/throttle_running_jobs'
      autoload :Worker,              'rocket_job/plugins/job/worker'
    end
    module Rufus
      autoload :CronLine,       'rocket_job/plugins/rufus/cron_line'
      autoload :ZoTime,         'rocket_job/plugins/rufus/zo_time'
    end
    autoload :Cron,             'rocket_job/plugins/cron'
    autoload :Document,         'rocket_job/plugins/document'
    autoload :ProcessingWindow, 'rocket_job/plugins/processing_window'
    autoload :Restart,          'rocket_job/plugins/restart'
    autoload :Singleton,        'rocket_job/plugins/singleton'
    autoload :StateMachine,     'rocket_job/plugins/state_machine'
  end

  module Jobs
    autoload :ActiveJob,        'rocket_job/jobs/active_job'
    autoload :DirmonJob,        'rocket_job/jobs/dirmon_job'
    autoload :HousekeepingJob,  'rocket_job/jobs/housekeeping_job'
    autoload :SimpleJob,        'rocket_job/jobs/simple_job'
  end
end

# Add Active Job adapter for Rails
require 'rocket_job/extensions/rocket_job_adapter' if defined?(ActiveJob)

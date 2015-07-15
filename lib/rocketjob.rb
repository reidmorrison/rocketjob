# encoding: UTF-8
require 'mongo'
require 'mongo_ha'
require 'mongo_mapper'
require 'semantic_logger'
require 'rocket_job/version'

module RocketJob
  autoload :CLI,                   'rocket_job/cli'
  autoload :Config,                'rocket_job/config'
  autoload :DirmonEntry,           'rocket_job/dirmon_entry'
  autoload :Heartbeat,             'rocket_job/heartbeat'
  autoload :Job,                   'rocket_job/job'
  autoload :JobException,          'rocket_job/job_exception'
  autoload :Server,                'rocket_job/server'
  module Concerns
    autoload :Worker,              'rocket_job/concerns/worker'
  end
  module Jobs
    autoload :DirmonJob,           'rocket_job/jobs/dirmon_job'
  end
end

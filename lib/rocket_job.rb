# encoding: UTF-8
require 'mongo'
require 'mongo_ha'
require 'mongo_mapper'
require 'semantic_logger'
require 'rocket_job/version'

module RocketJob
  autoload :CLI,                   'rocket_job/cli'
  autoload :Config,                'rocket_job/config'
  autoload :Heartbeat,             'rocket_job/heartbeat'
  autoload :Job,                   'rocket_job/job'
  autoload :JobException,          'rocket_job/job_exception'
  autoload :SlicedJob,             'rocket_job/sliced_job'
  autoload :Server,                'rocket_job/server'
  autoload :Worker,                'rocket_job/worker'
  autoload :Streams,               'rocket_job/streams'
  module Utility
    autoload :CSVRow,              'rocket_job/utility/csv_row'
  end
  module Jobs
    autoload :PerformanceJob,      'rocket_job/jobs/performance_job'
  end
  module Sliced
    autoload :Slice,               'rocket_job/sliced/slice'
    autoload :Slices,              'rocket_job/sliced/slices'
    autoload :Input,               'rocket_job/sliced/input'
    autoload :Output,              'rocket_job/sliced/output'
  end

  UTF8_ENCODING      = Encoding.find("UTF-8").freeze
  BINARY_ENCODING    = Encoding.find("BINARY").freeze
end

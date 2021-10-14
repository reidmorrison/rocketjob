require "iostreams"
require "semantic_logger"
require "symmetric-encryption"
require "mongoid"
require "rocket_job/extensions/mongo/logging"
require "rocket_job/extensions/iostreams/path"
require "rocket_job/extensions/psych/yaml_tree"
require "rocket_job/version"
require "rocket_job/rocket_job"
require "rocket_job/config"
require "rocket_job/railtie" if defined?(Rails)

# Apply patches to implement `with_collection`
require "rocket_job/extensions/mongoid/clients/options"
require "rocket_job/extensions/mongoid/contextual/mongo"
require "rocket_job/extensions/mongoid/factory"

# Backport New StringifiedSymbol type in Mongoid v7.2
require "rocket_job/extensions/mongoid/stringified_symbol" unless defined?(Mongoid::StringifiedSymbol)

# @formatter:off
module RocketJob
  autoload :ActiveWorker,            "rocket_job/active_worker"
  autoload :Batch,                   "rocket_job/batch"
  autoload :CLI,                     "rocket_job/cli"
  autoload :DirmonEntry,             "rocket_job/dirmon_entry"
  autoload :Event,                   "rocket_job/event"
  autoload :Heartbeat,               "rocket_job/heartbeat"
  autoload :Job,                     "rocket_job/job"
  autoload :JobException,            "rocket_job/job_exception"
  autoload :LookupCollection,        "rocket_job/lookup_collection"
  autoload :Worker,                  "rocket_job/worker"
  autoload :Performance,             "rocket_job/performance"
  autoload :RactorWorker,            "rocket_job/ractor_worker"
  autoload :Server,                  "rocket_job/server"
  autoload :Sliced,                  "rocket_job/sliced"
  autoload :Subscriber,              "rocket_job/subscriber"
  autoload :Supervisor,              "rocket_job/supervisor"
  autoload :ThreadWorker,            "rocket_job/thread_worker"
  autoload :ThrottleDefinition,      "rocket_job/throttle_definition"
  autoload :ThrottleDefinitions,     "rocket_job/throttle_definitions"
  autoload :WorkerPool,              "rocket_job/worker_pool"

  module Category
    autoload :Base,                  "rocket_job/category/base"
    autoload :Input,                 "rocket_job/category/input"
    autoload :Output,                "rocket_job/category/output"
  end

  module Plugins
    module Job
      autoload :Callbacks,           "rocket_job/plugins/job/callbacks"
      autoload :Defaults,            "rocket_job/plugins/job/defaults"
      autoload :StateMachine,        "rocket_job/plugins/job/state_machine"
      autoload :Logger,              "rocket_job/plugins/job/logger"
      autoload :Model,               "rocket_job/plugins/job/model"
      autoload :Persistence,         "rocket_job/plugins/job/persistence"
      autoload :Throttle,            "rocket_job/plugins/job/throttle"
      autoload :ThrottleRunningJobs, "rocket_job/plugins/job/throttle_running_jobs"
      autoload :Transaction,         "rocket_job/plugins/job/transaction"
      autoload :Worker,              "rocket_job/plugins/job/worker"
    end
    autoload :Cron,                  "rocket_job/plugins/cron"
    autoload :Document,              "rocket_job/plugins/document"
    autoload :ProcessingWindow,      "rocket_job/plugins/processing_window"
    autoload :Retry,                 "rocket_job/plugins/retry"
    autoload :Singleton,             "rocket_job/plugins/singleton"
    autoload :StateMachine,          "rocket_job/plugins/state_machine"
    autoload :Transaction,           "rocket_job/plugins/transaction"
    autoload :ThrottleDependentJobs, "rocket_job/plugins/throttle_dependent_jobs"
  end

  module Jobs
    autoload :ActiveJob,             "rocket_job/jobs/active_job"
    autoload :ConversionJob,         "rocket_job/jobs/conversion_job"
    autoload :CopyFileJob,           "rocket_job/jobs/copy_file_job"
    autoload :DirmonJob,             "rocket_job/jobs/dirmon_job"
    autoload :HousekeepingJob,       "rocket_job/jobs/housekeeping_job"
    autoload :OnDemandBatchJob,      "rocket_job/jobs/on_demand_batch_job"
    autoload :OnDemandJob,           "rocket_job/jobs/on_demand_job"
    autoload :PerformanceJob,        "rocket_job/jobs/performance_job"
    autoload :SimpleJob,             "rocket_job/jobs/simple_job"
    autoload :UploadFileJob,         "rocket_job/jobs/upload_file_job"

    module ReEncrypt
      autoload :RelationalJob,       "rocket_job/jobs/re_encrypt/relational_job"
    end
  end

  module Subscribers
    autoload :Logger,                "rocket_job/subscribers/logger"
    autoload :SecretConfig,          "rocket_job/subscribers/secret_config"
    autoload :Server,                "rocket_job/subscribers/server"
    autoload :Worker,                "rocket_job/subscribers/worker"
  end
end

# Add Active Job adapter for Rails
require "rocket_job/extensions/rocket_job_adapter" if defined?(ActiveJob)

require "iostreams"
require "semantic_logger"
require "symmetric-encryption"
require "mongoid"
require "rocket_job/extensions/mongo/logging"
require "rocket_job/version"
require "rocket_job/rocket_job"
require "rocket_job/config"
require "rocket_job/railtie" if defined?(Rails)

# Apply patches to implement `with_collection`
if Mongoid::VERSION.to_i >= 6
  require "rocket_job/extensions/mongoid/clients/options"
  require "rocket_job/extensions/mongoid/contextual/mongo"
  require "rocket_job/extensions/mongoid/factory"
else
  require "rocket_job/extensions/mongoid_5/clients/options"
  require "rocket_job/extensions/mongoid_5/contextual/mongo"
  require "rocket_job/extensions/mongoid_5/factory"
end

# @formatter:off
module RocketJob
  autoload :ActiveWorker,       "rocket_job/active_worker"
  autoload :Batch,              "rocket_job/batch"
  autoload :CLI,                "rocket_job/cli"
  autoload :DirmonEntry,        "rocket_job/dirmon_entry"
  autoload :Event,              "rocket_job/event"
  autoload :Heartbeat,          "rocket_job/heartbeat"
  autoload :Job,                "rocket_job/job"
  autoload :JobException,       "rocket_job/job_exception"
  autoload :Worker,             "rocket_job/worker"
  autoload :Performance,        "rocket_job/performance"
  autoload :Server,             "rocket_job/server"
  autoload :Subscriber,         "rocket_job/subscriber"
  autoload :Supervisor,         "rocket_job/supervisor"
  autoload :ThrottleDefinition, "rocket_job/throttle_definition"
  autoload :ThrottleDefinitions, "rocket_job/throttle_definitions"
  autoload :WorkerPool, "rocket_job/worker_pool"

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
    module Rufus
      autoload :CronLine,       "rocket_job/plugins/rufus/cron_line"
      autoload :ZoTime,         "rocket_job/plugins/rufus/zo_time"
    end
    autoload :Cron,             "rocket_job/plugins/cron"
    autoload :Document,         "rocket_job/plugins/document"
    autoload :ProcessingWindow, "rocket_job/plugins/processing_window"
    autoload :Restart,          "rocket_job/plugins/restart"
    autoload :Retry,            "rocket_job/plugins/retry"
    autoload :Singleton,        "rocket_job/plugins/singleton"
    autoload :StateMachine,     "rocket_job/plugins/state_machine"
    autoload :Transaction,      "rocket_job/plugins/transaction"
  end

  module Jobs
    autoload :ActiveJob,               "rocket_job/jobs/active_job"
    autoload :CopyFileJob,             "rocket_job/jobs/copy_file_job"
    autoload :DirmonJob,               "rocket_job/jobs/dirmon_job"
    autoload :OnDemandBatchJob,        "rocket_job/jobs/on_demand_batch_job"
    autoload :OnDemandBatchTabularJob, "rocket_job/jobs/on_demand_batch_tabular_job"
    autoload :OnDemandJob,             "rocket_job/jobs/on_demand_job"
    autoload :HousekeepingJob,         "rocket_job/jobs/housekeeping_job"
    autoload :PerformanceJob,          "rocket_job/jobs/performance_job"
    autoload :SimpleJob,               "rocket_job/jobs/simple_job"
    autoload :UploadFileJob,           "rocket_job/jobs/upload_file_job"
    module ReEncrypt
      autoload :RelationalJob, "rocket_job/jobs/re_encrypt/relational_job"
    end
  end

  module Sliced
    autoload :CompressedSlice,  "rocket_job/sliced/compressed_slice"
    autoload :EncryptedSlice,   "rocket_job/sliced/encrypted_slice"
    autoload :Input,            "rocket_job/sliced/input"
    autoload :Output,           "rocket_job/sliced/output"
    autoload :Slice,            "rocket_job/sliced/slice"
    autoload :Slices,           "rocket_job/sliced/slices"
    autoload :Store,            "rocket_job/sliced/store"

    module Writer
      autoload :Input,          "rocket_job/sliced/writer/input"
      autoload :Output,         "rocket_job/sliced/writer/output"
    end
  end

  module Subscribers
    autoload :Logger,           "rocket_job/subscribers/logger"
    autoload :Server,           "rocket_job/subscribers/server"
    autoload :Worker,           "rocket_job/subscribers/worker"
  end
end

# Add Active Job adapter for Rails
require "rocket_job/extensions/rocket_job_adapter" if defined?(ActiveJob)

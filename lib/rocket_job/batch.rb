require "active_support/concern"
require "rocket_job/batch/callbacks"
require "rocket_job/batch/io"
require "rocket_job/batch/logger"
require "rocket_job/batch/model"
require "rocket_job/batch/state_machine"
require "rocket_job/batch/throttle"
require "rocket_job/batch/throttle_running_workers"
require "rocket_job/batch/worker"
# Ensure after_perform is run first and #upload override is after IO#upload is defined.
require "rocket_job/batch/categories"

module RocketJob
  module Batch
    extend ActiveSupport::Concern

    include Model
    include StateMachine
    include Callbacks
    include Logger
    include Worker
    include Categories
    include Throttle
    include ThrottleRunningWorkers
    include IO

    autoload :LowerPriority, "rocket_job/batch/lower_priority"
    autoload :Performance, "rocket_job/batch/performance"
    autoload :Statistics, "rocket_job/batch/statistics"
    autoload :ThrottleWindows, "rocket_job/batch/throttle_windows"
    autoload :Result, "rocket_job/batch/result"
    autoload :Results, "rocket_job/batch/results"
  end
end

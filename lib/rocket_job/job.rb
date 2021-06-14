module RocketJob
  # The base job from which all jobs are created
  class Job
    include SemanticLogger::Loggable
    include Plugins::Document
    include Plugins::Job::Model
    include Plugins::Job::Persistence
    include Plugins::Job::Callbacks
    include Plugins::Job::Logger
    include Plugins::StateMachine
    include Plugins::Job::StateMachine
    include Plugins::Job::Worker
    include Plugins::Job::Throttle
    include Plugins::Job::ThrottleRunningJobs
    include Plugins::Job::ThrottleDependantJobs
  end
end

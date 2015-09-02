# encoding: UTF-8
require 'aasm'
module RocketJob
  # The base job from which all jobs are created
  class Job
    include MongoMapper::Document
    include AASM
    include SemanticLogger::Loggable
    include Concerns::Worker

    # Prevent data in MongoDB from re-defining the model behavior
    #self.static_keys = true

    #
    # User definable attributes
    #
    # The following attributes are set when the job is created
    # @formatter:off

    # Description for this job instance
    key :description,             String

    # Method that must be invoked to complete this job
    key :perform_method,          Symbol, default: :perform

    # Priority of this job as it relates to other jobs [1..100]
    #   1: Highest Priority
    #  50: Default Priority
    # 100: Lowest Priority
    #
    # Example:
    #   A job with a priority of 40 will execute before a job with priority 50
    #
    # In RocketJob Pro, if a SlicedJob is running and a higher priority job
    # arrives, then the current job will complete the current slices and process
    # the new higher priority job
    key :priority,                Integer, default: 50

    # Run this job no earlier than this time
    key :run_at,                  Time

    # If a job has not started by this time, destroy it
    key :expires_at,              Time

    # When specified a job will be re-scheduled to run at it's next scheduled interval
    # Format is the same as cron.
    # #TODO Future capability.
    #key :schedule,                String

    # When the job completes destroy it from both the database and the UI
    key :destroy_on_complete,     Boolean, default: true

    # Any user supplied arguments for the method invocation
    # All keys must be UTF-8 strings. The values can be any valid BSON type:
    #   Integer
    #   Float
    #   Time    (UTC)
    #   String  (UTF-8)
    #   Array
    #   Hash
    #   True
    #   False
    #   Symbol
    #   nil
    #   Regular Expression
    #
    # Note: Date is not supported, convert it to a UTC time
    key :arguments,               Array

    # Whether to store the results from this job
    key :collect_output,          Boolean, default: false

    # Raise or lower the log level when calling the job
    # Can be used to reduce log noise, especially during high volume calls
    # For debugging a single job can be logged at a low level such as :trace
    #   Levels supported: :trace, :debug, :info, :warn, :error, :fatal
    key :log_level,               Symbol

    #
    # Read-only attributes
    #

    # Current state, as set by AASM
    key :state,                   Symbol, default: :queued

    # When the job was created
    key :created_at,              Time, default: -> { Time.now }

    # When processing started on this job
    key :started_at,              Time

    # When the job completed processing
    key :completed_at,            Time

    # Number of times that this job has failed to process
    key :failure_count,           Integer, default: 0

    # This name of the worker that this job is being processed by, or was processed by
    key :worker_name,             String

    #
    # Values that jobs can update during processing
    #

    # Allow a job to updates its estimated progress
    # Any integer from 0 to 100
    key :percent_complete,        Integer, default: 0

    # Store the last exception for this job
    one :exception,               class_name: 'RocketJob::JobException'

    # Store the Hash result from this job if collect_output is true,
    # and the job returned actually returned a Hash, otherwise nil
    # Not applicable to SlicedJob jobs, since its output is stored in a
    # separate collection
    key :result,                  Hash

    # Store all job types in this collection
    set_collection_name 'rocket_job.jobs'

    validates_presence_of :state, :failure_count, :created_at, :perform_method
    validates :priority, inclusion: 1..100

    # State Machine events and transitions
    #
    #   :queued -> :running -> :completed
    #                       -> :paused     -> :running
    #                                      -> :aborted
    #                       -> :failed     -> :running
    #                                      -> :aborted
    #                       -> :aborted
    #                       -> :queued (when a worker dies)
    #           -> :aborted
    aasm column: :state do
      # Job has been created and is queued for processing ( Initial state )
      state :queued, initial: true

      # Job is running
      state :running

      # Job has completed processing ( End state )
      state :completed

      # Job is temporarily paused and no further processing will be completed
      # until this job has been resumed
      state :paused

      # Job failed to process and needs to be manually re-tried or aborted
      state :failed

      # Job was aborted and cannot be resumed ( End state )
      state :aborted

      event :start, before: :before_start do
        transitions from: :queued, to: :running
      end

      event :complete, before: :before_complete do
        after do
          destroy if destroy_on_complete
        end
        transitions from: :running, to: :completed
      end

      event :fail, before: :before_fail do
        transitions from: :queued,  to: :failed
        transitions from: :running, to: :failed
        transitions from: :paused,  to: :failed
      end

      event :retry, before: :before_retry do
        transitions from: :failed, to: :queued
      end

      event :pause, before: :before_pause do
        transitions from: :running, to: :paused
      end

      event :resume, before: :before_resume do
        transitions from: :paused, to: :running
      end

      event :abort, before: :before_abort do
        transitions from: :running, to: :aborted
        transitions from: :queued,  to: :aborted
        transitions from: :failed,  to: :aborted
        transitions from: :paused,  to: :aborted
      end

      event :requeue, before: :before_requeue do
        transitions from: :running, to: :queued
      end
    end
    # @formatter:on

    # Create indexes
    def self.create_indexes
      # Used by find_and_modify in .next_job
      ensure_index({state: 1, run_at: 1, priority: 1, created_at: 1, sub_state: 1}, background: true)
      # Remove outdated index if present
      drop_index('state_1_priority_1_created_at_1_sub_state_1') rescue nil
      # Used by Mission Control
      ensure_index [[:created_at, 1]]
    end

    # Requeues all jobs that were running on worker that died
    def self.requeue_dead_worker(worker_name)
      running.each { |job| job.requeue!(worker_name) }
    end

    # Pause all running jobs
    def self.pause_all
      running.each(&:pause!)
    end

    # Resume all paused jobs
    def self.resume_all
      paused.each(&:resume!)
    end

    # Returns the number of required arguments for this job
    def self.argument_count(method = :perform)
      instance_method(method).arity
    end

    # Returns [true|false] whether to collect the results from running this batch
    def collect_output?
      collect_output == true
    end

    # Returns [Float] the number of seconds the job has taken
    # - Elapsed seconds to process the job from when a worker first started working on it
    #   until now if still running, or until it was completed
    # - Seconds in the queue if queued
    def seconds
      if completed_at
        completed_at - (started_at || created_at)
      elsif started_at
        Time.now - started_at
      else
        Time.now - created_at
      end
    end

    # Returns a human readable duration the job has taken
    def duration
      RocketJob.seconds_as_duration(seconds)
    end

    # A job has expired if the expiry time has passed before it is started
    def expired?
      started_at.nil? && expires_at && (expires_at < Time.now)
    end

    # Returns [Hash] status of this job
    def as_json
      attrs = serializable_hash(methods: [:seconds, :duration])
      attrs.delete('result') unless collect_output?
      case
      when running?
        attrs.delete('completed_at')
        attrs.delete('result')
        attrs
      when paused?
        attrs.delete('completed_at')
        attrs.delete('result')
        # Ensure 'paused_at' appears first in the hash
        {'paused_at' => completed_at}.merge(attrs)
      when aborted?
        attrs.delete('completed_at')
        attrs.delete('result')
        {'aborted_at' => completed_at}.merge(attrs)
      when failed?
        attrs.delete('completed_at')
        attrs.delete('result')
        {'failed_at' => completed_at}.merge(attrs)
      else
        attrs
      end
    end

    def status(time_zone = 'Eastern Time (US & Canada)')
      h = as_json
      h.delete('seconds')
      h.delete('perform_method') if h['perform_method'] == :perform
      h.dup.each_pair do |k, v|
        case
        when v.is_a?(Time)
          h[k] = v.in_time_zone(time_zone).to_s
        when v.is_a?(BSON::ObjectId)
          h[k] = v.to_s
        end
      end
      h
    end

    # Patch the way MongoMapper reloads a model
    # Only reload MongoMapper attributes, leaving other instance variables untouched
    def reload
      if (doc = collection.find_one(_id: id))
        # Clear out keys that are not returned during the reload from MongoDB
        (keys.keys - doc.keys).each { |key| send("#{key}=", nil) }
        initialize_default_values
        load_from_database(doc)
        self
      else
        if destroy_on_complete
          self.state = :completed
          before_complete
        else
          raise(MongoMapper::DocumentNotFound, "Document match #{_id.inspect} does not exist in #{collection.name} collection")
        end
      end
    end

    # After this model is read, convert any hashes in the arguments list to HashWithIndifferentAccess
    def load_from_database(*args)
      super
      if arguments.present?
        self.arguments = arguments.collect { |i| i.is_a?(BSON::OrderedHash) ? i.with_indifferent_access : i }
      end
    end

    # Set exception information for this job and fail it
    def fail(worker_name='user', exc_or_message='Job failed through user action')
      if exc_or_message.is_a?(Exception)
        self.exception        = JobException.from_exception(exc_or_message)
        exception.worker_name = worker_name
      else
        build_exception(
          class_name:  'RocketJob::JobException',
          message:     exc_or_message,
          backtrace:   [],
          worker_name: worker_name
        )
      end
      # not available as #super
      aasm.current_event = :fail
      aasm_fire_event(:fail, persist: false)
    end

    def fail!(worker_name='user', exc_or_message='Job failed through user action')
      self.fail(worker_name, exc_or_message)
      save!
    end

    # Requeue this running job since the worker assigned to it has died
    def requeue!(worker_name_=nil)
      return false if worker_name_ && (worker_name != worker_name_)
      # not available as #super
      aasm.current_event = :requeue!
      aasm_fire_event(:requeue, persist: true)
    end

    # Requeue this running job since the worker assigned to it has died
    def requeue(worker_name_=nil)
      return false if worker_name_ && (worker_name != worker_name_)
      # not available as #super
      aasm.current_event = :requeue
      aasm_fire_event(:requeue, persist: false)
    end

    ############################################################################
    protected

    # Before events that can be overridden by child classes
    def before_start
      self.started_at = Time.now
    end

    def before_complete
      self.percent_complete = 100
      self.completed_at     = Time.now
      self.worker_name      = nil
    end

    def before_fail
      self.completed_at  = Time.now
      self.worker_name   = nil
      self.failure_count += 1
    end

    def before_retry
      self.completed_at = nil
      self.exception = nil
    end

    def before_pause
      self.completed_at = Time.now
      self.worker_name  = nil
    end

    def before_resume
      self.completed_at = nil
    end

    def before_abort
      self.completed_at = Time.now
      self.worker_name  = nil
    end

    def before_requeue
      self.started_at  = nil
      self.worker_name = nil
    end

  end
end

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
    key :arguments,               Array,    default: []

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
        transitions from: :failed, to: :running
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
    end
    # @formatter:on

    # Create indexes
    def self.create_indexes
      # Used by find_and_modify in .next_job
      ensure_index({ state: 1, run_at: 1, priority: 1, created_at: 1, sub_state: 1 }, background: true)
      # Remove outdated index if present
      drop_index("state_1_priority_1_created_at_1_sub_state_1") rescue nil
      # Used by Mission Control
      ensure_index [[:created_at, 1]]
    end

    # Requeue all jobs for the specified dead worker
    def self.requeue_dead_worker(worker_name)
      collection.update(
        { 'worker_name' => worker_name, 'state' => :running },
        { '$unset' => { 'worker_name' => true, 'started_at' => true }, '$set' => { 'state' => :queued } },
        multi: true
      )
    end

    # Pause all running jobs
    def self.pause_all
      where(state: 'running').each { |job| job.pause! }
    end

    # Resume all paused jobs
    def self.resume_all
      where(state: 'paused').each { |job| job.resume! }
    end

    # Returns the number of required arguments for this job
    def self.argument_count(method=:perform)
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
      seconds_as_duration(seconds)
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
        { 'paused_at' => completed_at }.merge(attrs)
      when aborted?
        attrs.delete('completed_at')
        attrs.delete('result')
        { 'aborted_at' => completed_at }.merge(attrs)
      when failed?
        attrs.delete('completed_at')
        attrs.delete('result')
        { 'failed_at' => completed_at }.merge(attrs)
      else
        attrs
      end
    end

    def status(time_zone='Eastern Time (US & Canada)')
      h = as_json
      h.delete('seconds')
      h.delete('perform_method') if h['perform_method'] == :perform
      h.dup.each_pair do |k, v|
        case
        when v.kind_of?(Time)
          h[k] = v.in_time_zone(time_zone).to_s
        when v.kind_of?(BSON::ObjectId)
          h[k] = v.to_s
        end
      end
      h
    end

    # TODO Jobs are not currently automatically retried. Is there a need?
    def seconds_to_delay(count)
      # TODO Consider lowering the priority automatically after every retry?
      # Same basic formula for calculating retry interval as delayed_job and Sidekiq
      (count ** 4) + 15 + (rand(30)*(count+1))
    end

    # Patch the way MongoMapper reloads a model
    # Only reload MongoMapper attributes, leaving other instance variables untouched
    def reload
      if doc = collection.find_one(:_id => id)
        load_from_database(doc)
        self
      else
        raise MongoMapper::DocumentNotFound, "Document match #{_id.inspect} does not exist in #{collection.name} collection"
      end
    end

    # After this model is read, convert any hashes in the arguments list to HashWithIndifferentAccess
    def load_from_database(*args)
      super
      self.arguments = arguments.collect { |i| i.is_a?(BSON::OrderedHash) ? i.with_indifferent_access : i } if arguments.present?
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
      self.completed_at = Time.now
      self.worker_name  = nil
    end

    def before_retry
      self.completed_at = nil
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

    # Returns a human readable duration from the supplied [Float] number of seconds
    def seconds_as_duration(seconds)
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

    # Returns the next job to work on in priority based order
    # Returns nil if there are currently no queued jobs, or processing batch jobs
    #   with records that require processing
    #
    # Parameters
    #   worker_name [String]
    #     Name of the worker that will be processing this job
    #
    #   skip_job_ids [Array<BSON::ObjectId>]
    #     Job ids to exclude when looking for the next job
    #
    # Note:
    #   If a job is in queued state it will be started
    def self.next_job(worker_name, skip_job_ids = nil)
      query        = {
        '$and' => [
          {
            '$or' => [
              { 'state' => 'queued' }, # Jobs
              { 'state' => 'running', 'sub_state' => :processing } # Slices
            ]
          },
          {
            '$or' => [
              { run_at: { '$exists' => false } },
              { run_at: { '$lte' => Time.now } }
            ]
          },
        ]
      }
      query['_id'] = { '$nin' => skip_job_ids } if skip_job_ids && skip_job_ids.size > 0

      while doc = find_and_modify(
        query:  query,
        sort:   [['priority', 'asc'], ['created_at', 'asc']],
        update: { '$set' => { 'worker_name' => worker_name, 'state' => 'running' } }
      )
        job = load(doc)
        if job.running?
          return job
        else
          if job.expired?
            job.destroy
            logger.info "Destroyed expired job #{job.class.name}, id:#{job.id}"
          else
            # Also update in-memory state and run call-backs
            job.start
            job.set(started_at: job.started_at)
            return job
          end
        end
      end
    end

    ############################################################################
    private

    # Set exception information for this job
    def set_exception(worker_name, exc)
      self.worker_name      = nil
      self.failure_count    += 1
      self.exception        = JobException.from_exception(exc)
      exception.worker_name = worker_name
      fail! unless failed?
      logger.error("Exception running #{self.class.name}##{perform_method}", exc)
    end

    # Calls a method on this job, if it is defined
    # Adds the event name to the method call if supplied
    #
    # Returns [Object] the result of calling the method
    #
    # Parameters
    #   method [Symbol]
    #     The method to call on this job
    #
    #   arguments [Array]
    #     Arguments to pass to the method call
    #
    #   Options:
    #     event: [Symbol]
    #       Any one of: :before, :after
    #       Default: None, just calls the method itself
    #
    #     log_level: [Symbol]
    #       Log level to apply to silence logging during the call
    #       Default: nil ( no change )
    #
    def call_method(method, arguments, options={})
      options   = options.dup
      event     = options.delete(:event)
      log_level = options.delete(:log_level)
      raise(ArgumentError, "Unknown #{self.class.name}#call_method options: #{options.inspect}") if options.size > 0

      the_method = event.nil? ? method : "#{event}_#{method}".to_sym
      if respond_to?(the_method)
        method_name = "#{self.class.name}##{the_method}"
        logger.info "Start #{method_name}"
        logger.benchmark_info("Completed #{method_name}",
          metric:             "rocketjob/#{self.class.name.underscore}/#{the_method}",
          log_exception:      :full,
          on_exception_level: :error,
          silence:            log_level
        ) do
          self.send(the_method, *arguments)
        end
      end
    end

  end
end

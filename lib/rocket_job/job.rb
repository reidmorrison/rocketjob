# encoding: UTF-8
require 'aasm'
module RocketJob
  # The base job from which all jobs are created
  class Job
    include SemanticLogger::Loggable
    include MongoMapper::Document
    include Concerns::EventCallbacks
    include Concerns::Callbacks
    include Concerns::StateMachine
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
    validates :log_level, inclusion: SemanticLogger::LEVELS + [nil]

    # User definable properties in Dirmon Entry
    def self.rocket_job_properties
      @rocket_job_properties ||= (self == RocketJob::Job ? [] : superclass.rocket_job_properties)
    end

    # Add to user definable properties in Dirmon Entry
    def self.public_rocket_job_properties(*properties)
      rocket_job_properties.concat(properties).uniq!
    end

    # User definable properties in Dirmon Entry
    public_rocket_job_properties :description, :priority, :perform_method, :log_level, :arguments

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
      running.each { |job| job.requeue!(worker_name) if job.may_requeue?(worker_name) }
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

    # Override parent defaults
    def self.rocket_job(&block)
      @rocket_job_defaults = block
      self
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

    # Returns [Hash] the status of this job
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

    # Sets the exception child object for this job based on the
    # supplied Exception instance or message
    def set_exception(worker_name='', exc_or_message='')
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
          set_completed_at
          mark_complete
        else
          raise(MongoMapper::DocumentNotFound, "Document match #{_id.inspect} does not exist in #{collection.name} collection")
        end
      end
    end

    # Patch AASM so that save! is called instead of save
    # So that validations are run before job.requeue! is completed
    # Otherwise it just fails silently
    def aasm_write_state(state, name=:default)
      attr_name = self.class.aasm(name).attribute_name
      old_value = read_attribute(attr_name)
      write_attribute(attr_name, state)

      begin
        if aasm_skipping_validations(name)
          saved = save(validate: false)
          write_attribute(attr_name, old_value) unless saved
          saved
        else
          save!
        end
      rescue Exception => exc
        write_attribute(attr_name, old_value)
        raise(exc)
      end
    end

    private

    # After this model is loaded, convert any hashes in the arguments list to HashWithIndifferentAccess
    def load_from_database(*args)
      super
      if arguments.present?
        self.arguments = arguments.collect { |i| i.is_a?(BSON::OrderedHash) ? i.with_indifferent_access : i }
      end
    end

    def self.apply_defaults(job)
      @rocket_job_defaults.call(job) if @rocket_job_defaults
    end

    # Apply RocketJob defaults after initializing default values
    # but before setting attributes
    def initialize_default_values(except = {})
      super
      self.class.apply_defaults(self)
    end

  end
end

# encoding: UTF-8
require 'aasm'
module RocketJob
  # Rocket Job identifies each batch job submission
  #
  # - Make it an expired collection with purging of jobs completed_at older than 14 days
  #
  # Rocket Job is a global "priority based queue" (wikipedia link).
  # All jobs are placed in a single global queue and the job with the highest priority
  # is always processed first.
  #
  # This differs from the traditional approach of separate
  # queues for jobs which quickly becomes cumbersome when their are for example
  # over a hundred different types of workers.
  #
  # The global priority based queue ensures that the servers are utilized to their
  # capacity without requiring constant manual intervention.
  #
  # Rocket Job is designed to handle upwards of hundreds of millions of concurrent
  # "jobs" that are often encountered in high volume batch processing environments.
  # It is designed from the ground up to support large batch file processing.
  # For example a single file that contains millions of records to be processed
  # as quickly as possible without impacting other batch jobs with a higher priority.
  #
  class Job
    include MongoMapper::Document
    include AASM
    include SemanticLogger::Loggable

    # Prevent data in MongoDB from re-defining the model behavior
    #self.static_keys = true

    #
    # User definable attributes
    #
    # The following attributes are set when the job is created

    # Description for this job instance
    key :description,             String

    # Class that implements this jobs behavior
    key :klass,                   String

    # Method that must be invoked to complete this job
    key :perform_method,          Symbol, default: :perform

    # Priority of this job as it relates to other jobs [1..100]
    #   1: Lowest Priority
    # 100: Highest Priority
    #  50: Default Priority
    key :priority,                Integer, default: 50

    # Support running this job in the future
    #   Also set when a job fails and needs to be re-tried in the future
    key :run_at,                  Time

    # If a job has not started by this time, destroy it
    key :expires_at,              Time

    # When specified a job will be re-scheduled to run at it's next scheduled interval
    # Format is the same as cron
    key :schedule,                String

    # Job should be marked as repeatable when it can be run multiple times
    # without changing the system state or modifying database contents.
    # Setting to false will result in an additional lookup on the results collection
    # before processing the record to ensure it was not previously processed.
    # This is necessary for retrying a job.
    key :repeatable,              Boolean, default: true

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

    # Only give access through the Web UI to this group identifier
    #key :group,                   String

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

    # This name of the server that this job is being processed by, or was processed by
    key :server_name,             String

    #
    # Values that jobs can update during processing
    #

    # Allow the worker to set how far it is in the job
    # Any integer from 0 to 100
    # For Multi-record jobs do not set this value directly
    key :percent_complete,        Integer, default: 0

    # Store the last exception for this job
    key :exception,               Hash

    # Store the Hash result from this job if collect_output is true,
    # and the job returned actually returned a Hash, otherwise nil
    # Not applicable to SlicedJob jobs, since its output is stored in a
    # separate collection
    key :result,                  Hash

    # Store all job types in this collection
    set_collection_name 'rocket_job.jobs'

    validates_presence_of :state, :failure_count, :created_at, :percent_complete,
      :klass, :perform_method
    # :repeatable, :destroy_on_complete, :collect_output, :arguments
    validates :percent_complete, inclusion: 0..100
    validates :priority, inclusion: 1..100

    # State Machine events and transitions
    #
    # For Job Record jobs, usual processing:
    #   :queued -> :running -> :completed
    #                       -> :paused     -> :running  ( manual )
    #                       -> :failed     -> :running  ( manual )
    #                       -> :retry      -> :running  ( future date )
    #
    # Any state other than :completed can transition manually to :aborted
    #
    # Work queue is priority based and then FIFO thereafter
    # means that records from existing multi-record jobs will be completed before
    # new jobs are started with the same priority.
    # Unless, the loader is not fast enough and the
    # records queue is empty. In this case the next multi-record job will
    # start loading too.
    #
    # Where: state: [:queued, :running], run_at: $lte: Time.now
    # Sort:  priority, created_at
    #
    # Index: state, run_at
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

      # Job failed to process previously and is scheduled to be retried at a
      # future date
      state :retry

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
        transitions from: :running, to: :failed
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

    # Create indexes
    def self.create_indexes
      ensure_index [[:state, 1], [:priority, 1], [:created_at, 1], [:sub_state, 1]]
    end

    # Requeue all jobs for the specified dead server
    def self.requeue_dead_server(server_name)
      collection.update(
        { 'server_name' => server_name, 'state' => :running },
        { '$unset' => { 'server_name' => true, 'started_at' => true }, '$set' => { 'state' => :queued } },
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

    # Returns [Hash] status of this job
    def status(time_zone='EST')
      h = {
        state:                state,
        description:          description
      }
      h[:started_at]         = started_at.in_time_zone(time_zone) if started_at

      case
      when running? || paused?
        if running?
          h[:status]         = started_at ? "Started at #{started_at.in_time_zone(time_zone)}" : "Started"
        else
          h[:status]         = "Paused at #{completed_at.in_time_zone(time_zone)}"
        end
        h[:seconds]          = started_at ? Time.now - started_at : 0
        h[:paused_at]        = completed_at.in_time_zone(time_zone) if paused?
        h[:percent_complete] = percent_complete if percent_complete
        h[:status]           = "Running for #{'%.2f' % h[:seconds]} seconds"
      when completed?
        h[:seconds]          = completed_at - started_at
        h[:status]           = "Completed at #{completed_at.in_time_zone(time_zone)}"
        h[:completed_at]     = completed_at.in_time_zone(time_zone)
      when queued?
        h[:seconds]          = Time.now - created_at
        h[:status]           = "Queued for #{'%.2f' % h[:seconds]} seconds"
      when aborted?
        h[:seconds]          = started_at ? completed_at - started_at : 0
        h[:status]           = "Aborted at #{completed_at.in_time_zone(time_zone)}"
        h[:aborted_at]       = completed_at.in_time_zone(time_zone)
        h[:percent_complete] = percent_complete if percent_complete
      when failed?
        h[:seconds]          = started_at ? completed_at - started_at : 0
        h[:status]           = "Failed at #{completed_at.in_time_zone(time_zone)}"
        h[:failed_at]        = completed_at.in_time_zone(time_zone)
        h[:percent_complete] = percent_complete if percent_complete
        h[:exception]        = exception.dup
      else
        h[:seconds]          = 0
        h[:status]           = "Unknown job state: #{state}"
      end
      h[:duration] = Time.at(h[:seconds]).strftime('%H:%M:%S')
      h
    end

    # Same basic formula for calculating retry interval as delayed_job and Sidekiq
    # TODO Consider lowering the priority automatically after every retry?
    def seconds_to_delay(count)
      (count ** 4) + 15 + (rand(30)*(count+1))
    end

    # Returns a new instance of the worker for this job
    def new_worker
      worker = klass.constantize.new
      worker.rocket_job = self
      worker
    end

    # Invokes the worker to process this job
    #
    # Returns the number of records processed
    #
    # If an exception is thrown the job is marked as failed and the exception
    # is set in the job itself.
    #
    # Thread-safe, can be called by multiple threads at the same time
    def work(server)
      raise 'Job must be started before calling #work' unless running?
      begin
        worker = new_worker
        # before_perform
        call_method(worker, :before)

        # perform
        result = call_method(worker)
        if self.collect_output?
          self.output = (result.is_a?(Hash) || result.is_a?(BSON::OrderedHash)) ? result : { result: result }
        end

        # after_perform
        call_method(worker, :after)
        complete!
        1
      rescue Exception => exc
        worker.on_exception(exc) if worker && worker.respond_to?(:on_exception)
        set_exception(server.name, exc)
        raise exc if RocketJob::Config.inline_mode
        0
      end
    end

    # Patch the way MongoMapper reloads a model
    def reload
      if doc = collection.find_one(:_id => id)
        load_from_database(doc)
        self
      else
        raise DocumentNotFound, "Document match #{_id.inspect} does not exist in #{collection.name} collection"
      end
    end

    protected

    # Before events that can be overridden by child classes
    def before_start
      self.started_at = Time.now
    end

    def before_complete
      self.percent_complete = 100
      self.completed_at = Time.now
    end

    def before_fail
      self.completed_at = Time.now
    end

    def before_retry
      self.completed_at = nil
    end

    def before_pause
      self.completed_at = Time.now
    end

    def before_resume
      self.completed_at = nil
    end

    def before_abort
      self.completed_at = Time.now
    end

    # Calls a method on the worker, if it is defined for the worker
    # Adds the event name to the method call if supplied
    #
    # Parameters
    #   worker [RocketJob::Worker]
    #     The worker instance on which to invoke the method
    #
    #   event [Symbol]
    #     Any one of: :before, :after
    #     Default: None, just call the method itself
    #
    def call_method(worker, event=nil)
      the_method = event.nil? ? self.perform_method : "#{event}_#{self.perform_method}".to_sym
      if worker.respond_to?(the_method)
        method_name = "#{worker.class.name}##{the_method}"
        logger.info "Start #{method_name}"
        logger.benchmark_info(
          "Completed #{method_name}",
          metric:             "rocket_job/#{worker.class.name.underscore}/#{the_method}",
          log_exception:      :full,
          on_exception_level: :error,
          silence:            self.log_level
        ) do
          worker.send(the_method, *self.arguments)
        end
      end
    end

    private

    # Set exception information for this job
    def set_exception(server_name, exc)
      self.server_name = nil
      self.failure_count += 1
      self.exception = {
        'class'         => exc.class.to_s,
        'message'       => exc.message,
        'backtrace'     => exc.backtrace || [],
        'server_name'   => server_name,
      }
      fail!
      logger.error("Exception running #{klass}##{perform_method}", exc)
    end

  end
end

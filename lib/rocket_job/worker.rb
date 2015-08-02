# encoding: UTF-8
require 'socket'
require 'sync_attr'
require 'aasm'
module RocketJob
  # Worker
  #
  # On startup a worker instance will automatically register itself
  # if not already present
  #
  # Starting a worker in the foreground:
  #   - Using a Rails runner:
  #     bin/rocketjob
  #
  # Starting a worker in the background:
  #   - Using a Rails runner:
  #     nohup bin/rocketjob --quiet 2>&1 1>output.log &
  #
  # Stopping a worker:
  #   - Stop the worker via the Web UI
  #   - Send a regular kill signal to make it shutdown once all active work is complete
  #       kill <pid>
  #   - Or, use the following Ruby code:
  #     worker = RocketJob::Worker.where(name: 'worker name').first
  #     worker.stop!
  #
  #   Sending the kill signal locally will result in starting the shutdown process
  #   immediately. Via the UI or Ruby code the worker can take up to 15 seconds
  #   (the heartbeat interval) to start shutting down.
  class Worker
    include MongoMapper::Document
    include AASM
    include SyncAttr
    include SemanticLogger::Loggable

    # Prevent data in MongoDB from re-defining the model behavior
    #self.static_keys = true

    # @formatter:off
    # Unique Name of this worker instance
    #   Defaults to the `hostname` but _must_ be overriden if mutiple Worker instances
    #   are started on the same host
    # The unique name is used on re-start to re-queue any jobs that were being processed
    # at the time the worker or host unexpectedly terminated, if any
    key :name,               String, default: -> { "#{Socket.gethostname}:#{$$}" }

    # The maximum number of threads that this worker should use
    #   If set, it will override the default value in RocketJob::Config
    key :max_threads,        Integer, default: -> { Config.instance.max_worker_threads }

    # When this worker process was started
    key :started_at,         Time

    # The heartbeat information for this worker
    one :heartbeat,          class_name: 'RocketJob::Heartbeat'

    # Current state
    #   Internal use only. Do not set this field directly
    key :state,              Symbol, default: :starting

    validates_presence_of :state, :name, :max_threads

    # States
    #   :starting -> :running -> :paused
    #                         -> :stopping
    aasm column: :state do
      state :starting, initial: true
      state :running
      state :paused
      state :stopping

      event :started do
        transitions from: :starting, to: :running
        before do
          self.started_at = Time.now
        end
      end
      event :pause do
        transitions from: :running, to: :paused
      end
      event :resume do
        transitions from: :paused, to: :running
      end
      event :stop do
        transitions from: :running,  to: :stopping
        transitions from: :paused,   to: :stopping
        transitions from: :starting, to: :stopping
      end
    end
    # @formatter:on

    attr_reader :thread_pool

    # Requeue any jobs being worked by this worker when it is destroyed
    before_destroy :requeue_jobs

    # Run the worker process
    # Attributes supplied are passed to #new
    def self.run(attrs={})
      worker = new(attrs)
      worker.build_heartbeat
      worker.save!
      create_indexes
      register_signal_handlers
      raise "The RocketJob configuration is being applied after the system has been initialized" unless RocketJob::Job.database.name == RocketJob::SlicedJob.database.name
      logger.info "Using MongoDB Database: #{RocketJob::Job.database.name}"
      worker.run
    end

    # Create indexes
    def self.create_indexes
      ensure_index [[:name, 1]], background: true, unique: true
      # Also create indexes for the jobs collection
      Job.create_indexes
    end

    # Destroy dead workers ( missed at least the last 4 heartbeats )
    # Requeue jobs assigned to dead workers
    # Destroy dead workers
    def self.destroy_dead_workers
      dead_seconds = Config.instance.heartbeat_seconds * 4
      each do |worker|
        next if (Time.now - worker.heartbeat.updated_at) < dead_seconds
        logger.warn "Destroying worker #{worker.name}, and requeueing its jobs"
        worker.destroy
      end
    end

    # Stop all running, paused, or starting workers
    def self.stop_all
      where(state: ['running', 'paused', 'starting']).each { |worker| worker.stop! }
    end

    # Pause all running workers
    def self.pause_all
      where(state: 'running').each { |worker| worker.pause! }
    end

    # Resume all paused workers
    def self.resume_all
      each { |worker| worker.resume! if worker.paused? }
    end

    # Register a handler to perform cleanups etc. whenever a worker is
    # explicitly destroyed
    def self.register_destroy_handler(&block)
      @@destroy_handlers << block
    end

    # Returns [Boolean] whether the worker is shutting down
    def shutting_down?
      if self.class.shutdown
        stop! if running?
        true
      else
        !running?
      end
    end

    # Returns [Array<Thread>] threads in the thread_pool
    def thread_pool
      @thread_pool ||= []
    end

    # Run this instance of the worker
    def run
      Thread.current.name = 'RocketJob main'
      build_heartbeat unless heartbeat

      started
      adjust_thread_pool(true)
      save
      logger.info "RocketJob Worker started with #{max_threads} workers running"

      count = 0
      loop do
        # Update heartbeat so that monitoring tools know that this worker is alive
        set(
          'heartbeat.updated_at'      => Time.now,
          'heartbeat.current_threads' => thread_pool_count
        )

        # Reload the worker model every 10 heartbeats in case its config was changed
        # TODO make 3 configurable
        if count >= 3
          reload
          adjust_thread_pool
          count = 0
        else
          count += 1
        end

        # Stop worker if shutdown signal was raised
        stop! if self.class.shutdown && !stopping?

        break if stopping?

        sleep Config.instance.heartbeat_seconds
      end
      logger.info 'Waiting for worker threads to stop'
      # TODO Put a timeout on join.
      # Log Thread dump for active threads
      # Compare thread dumps for any changes, force down if no change?
      # reload, if model missing: Send Shutdown exception to each thread
      #           5 more seconds then exit
      thread_pool.each { |t| t.join }
      logger.info 'Shutdown'
    rescue Exception => exc
      logger.error('RocketJob::Worker is stopping due to an exception', exc)
    ensure
      # Destroy this worker instance
      destroy
    end

    def thread_pool_count
      thread_pool.count { |i| i.alive? }
    end

    protected

    def next_worker_id
      @worker_id ||= 0
      @worker_id += 1
    end

    # Re-adjust the number of running threads to get it up to the
    # required number of threads
    #   Parameters
    #     stagger_threads
    #       Whether to stagger when the threads poll for work the first time
    #       It spreads out the queue polling over the max_poll_seconds so
    #       that not all workers poll at the same time
    #       The worker also respond faster than max_poll_seconds when a new
    #       job is added.
    def adjust_thread_pool(stagger_threads=false)
      count = thread_pool_count
      # Cleanup threads that have stopped
      if count != thread_pool.count
        logger.info "Cleaning up #{thread_pool.count - count} threads that went away"
        thread_pool.delete_if { |t| !t.alive? }
      end

      return if shutting_down?

      # Need to add more threads?
      if count < max_threads
        thread_count = max_threads - count
        logger.info "Starting #{thread_count} threads"
        thread_count.times.each do
          # Start worker thread
          thread_pool << Thread.new(next_worker_id) do |id|
            begin
              sleep (Config.instance.max_poll_seconds.to_f / max_threads) * (id - 1) if stagger_threads
              worker(id)
            rescue Exception => exc
              logger.fatal('Cannot start worker thread', exc)
            end
          end
        end
      end
    end

    # Keep processing jobs until worker stops running
    def worker(worker_id)
      Thread.current.name = "rocketjob #{worker_id}"
      logger.info 'Started'
      while !shutting_down?
        if process_next_job
          # Keeps workers staggered across the poll interval so that not
          # all workers poll at the same time
          sleep rand(RocketJob::Config.instance.max_poll_seconds * 1000) / 1000
        else
          sleep RocketJob::Config.instance.max_poll_seconds
        end
      end
      logger.info "Stopping. Worker state: #{state.inspect}"
    rescue Exception => exc
      logger.fatal('Unhandled exception in job processing thread', exc)
    end

    # Process the next available job
    # Returns [Boolean] whether any job was actually processed
    def process_next_job
      skip_job_ids = []
      while job = Job.next_job(name, skip_job_ids)
        logger.tagged("Job #{job.id}") do
          if job.work(self)
            return true if shutting_down?
            # Need to skip the specified job due to throttling or no work available
            skip_job_ids << job.id
          else
            return true
          end
        end
      end
      false
    end

    # Requeue any jobs assigned to this worker
    def requeue_jobs
      stop! if running? || paused?
      @@destroy_handlers.each { |handler| handler.call(name) }
    end

    # Mutex protected shutdown indicator
    sync_cattr_accessor :shutdown do
      false
    end

    # Register handlers for the various signals
    # Term:
    #   Perform clean shutdown
    #
    def self.register_signal_handlers
      begin
        Signal.trap "SIGTERM" do
          # Cannot use Mutex protected writer here since it is in a signal handler
          @@shutdown = true
          logger.warn "Shutdown signal (SIGTERM) received. Will shutdown as soon as active jobs/slices have completed."
        end

        Signal.trap "INT" do
          # Cannot use Mutex protected writer here since it is in a signal handler
          @@shutdown = true
          logger.warn "Shutdown signal (INT) received. Will shutdown as soon as active jobs/slices have completed."
        end
      rescue Exception
        logger.warn "SIGTERM handler not installed. Not able to shutdown gracefully"
      end
    end

    # Patch the way MongoMapper reloads a model
    def reload
      if doc = collection.find_one(:_id => id)
        load_from_database(doc)
        self
      else
        raise MongoMapper::DocumentNotFound, "Document match #{_id.inspect} does not exist in #{collection.name} collection"
      end
    end

    private

    @@destroy_handlers = ThreadSafe::Array.new

  end
end


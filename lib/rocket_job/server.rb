# encoding: UTF-8
require 'socket'
require 'sync_attr'
module RocketJob
  # Server
  #
  # On startup a server instance will automatically register itself
  # if not already present
  #
  # Starting a server in the foreground:
  #   - Using a Rails runner:
  #     bin/rails r 'RocketJob::Server.start'
  #
  #   - Or, using a rake task:
  #     bin/rake rocket_job:server
  #
  # Starting a server in the background:
  #   - Using a Rails runner:
  #     nohup bin/rails r 'RocketJob::Server.start' 2>&1 1>output.log &
  #
  #   - Or, using a rake task:
  #     nohup bin/rake rocket_job:server 2>&1 1>output.log &
  #
  # Stopping a server:
  #   - Stop the server via the Web UI
  #   - Send a regular kill signal to make it shutdown once all active work is complete
  #       kill <pid>
  #   - Or, use the following Ruby code:
  #     server = RocketJob::Server.where(name: 'server name').first
  #     server.stop!
  #
  #   Sending the kill signal locally will result in starting the shutdown process
  #   immediately. Via the UI or Ruby code the server can take up to 15 seconds
  #   (the heartbeat interval) to start shutting down.
  #
  # Restarting a server:
  #   - Restart the server via the Web UI
  #   - Or, use the following Ruby code:
  #     server = RocketJob::Server.where(name: 'server name').first
  #     server.restart!
  #
  #   It can take up to 30 seconds (the heartbeat interval) before the server re-starts
  #
  #
  class Server
    include MongoMapper::Document
    include AASM
    include SyncAttr
    include SemanticLogger::Loggable

    # Prevent data in MongoDB from re-defining the model behavior
    #self.static_keys = true

    # Unique Name of this server instance
    #   Defaults to the `hostname` but _must_ be overriden if mutiple Server instances
    #   are started on the same host
    # The unique name is used on re-start to re-queue any jobs that were being processed
    # at the time the server or host unexpectedly terminated, if any
    key :name,               String, default: -> { "#{Socket.gethostname}:#{$$}" }

    # The maximum number of worker threads
    #   If set, it will override the default value in RocketJob::Config
    key :max_threads,        Integer, default: -> { Config.instance.max_worker_threads }

    # When this server process was started
    key :started_at,         Time

    # The heartbeat information for this server
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

    attr_reader :thread_pool

    # Requeue any jobs being worked by this server when it is destroyed
    before_destroy :requeue_jobs

    # Run the server process
    # Attributes supplied are passed to #new
    def self.run(attrs={})
      server = new(attrs)
      server.build_heartbeat
      server.save!
      create_indexes
      register_signal_handlers
      server.run
    end

    # Create indexes
    def self.create_indexes
      ensure_index [[:name, 1]], background: true, unique: true
      # Also create indexes for the jobs collection
      Job.create_indexes
    end

    # Destroy dead servers ( missed at least the last 4 heartbeats )
    # Requeue jobs assigned to dead servers
    # Destroy dead servers
    def self.cleanup_dead_servers
      dead_seconds = Config.instance.heartbeat_seconds * 4
      each do |server|
        next if (Time.now - server.heartbeat.updated_at) < dead_seconds
        logger.warn "Destroying server #{server.name}, and requeueing its jobs"
        server.destroy
      end
    end

    # Stop all running, paused, or starting servers
    def self.stop_all
      where(state: ['running', 'paused', 'starting']).each { |server| server.stop! }
    end

    # Pause all running servers
    def self.pause_all
      where(state: 'running').each { |server| server.pause! }
    end

    # Resume all paused servers
    def self.resume_all
      each { |server| server.resume! if server.paused? }
    end

    # Returns [Array<Thread>] threads in the thread_pool
    def thread_pool
      @thread_pool ||= []
    end

    # Run this instance of the server
    def run
      Thread.current.name = 'RocketJob main'
      build_heartbeat unless heartbeat

      started
      adjust_thread_pool(true)
      save
      logger.info "RocketJob Server started with #{max_threads} workers running"

      count = 0
      loop do
        # Update heartbeat so that monitoring tools know that this server is alive
        set(
          'heartbeat.updated_at'      => Time.now,
          'heartbeat.current_threads' => thread_pool_count
        )

        # Reload the server model every 10 heartbeats in case its config was changed
        # TODO make 3 configurable
        if count >= 3
          reload
          adjust_thread_pool
          count = 0
        else
          count += 1
        end

        # Stop server if shutdown signal was raised
        stop! if @@shutdown && !stopping?

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
      logger.error('RocketJob::Server is stopping due to an exception', exc)
    ensure
      # Destroy this server instance
      destroy
    end

    def thread_pool_count
      thread_pool.count{ |i| i.alive? }
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

      return unless running?

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

    # Keep processing jobs until server stops running
    def worker(worker_id)
      Thread.current.name = "RocketJob Worker #{worker_id}"
      logger.info 'Started'
      loop do
        worked = false
        if job = Job.next_job(name)
          logger.tagged("Job #{job.id}") do
            job.work(self)
            worked = true
          end
        else
          if worked
            # Keeps workers staggered across the poll interval so that not
            # all workers poll again at the same time
            sleep rand(RocketJob::Config.instance.max_poll_seconds * 1000) / 1000
            worked = false
          else
            sleep RocketJob::Config.instance.max_poll_seconds
          end
        end
        break if @@shutdown || !running?
      end
      logger.info "Stopping. Server state: #{state.inspect}"
    rescue Exception => exc
      logger.fatal('Unhandled exception in job processing thread', exc)
    end

    # Requeue any jobs assigned to this server
    def requeue_jobs
      stop! if running? || paused?
      RocketJob::SlicedJob.requeue_dead_server(name)
    end

    @@shutdown = false

    # Register handlers for the various signals
    # Term:
    #   Perform clean shutdown
    #
    def self.register_signal_handlers
      begin
        Signal.trap "SIGTERM" do
          @@shutdown = true
          logger.warn "Shutdown signal (SIGTERM) received. Will shutdown as soon as active jobs/slices have completed."
        end

        Signal.trap "INT" do
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
        raise DocumentNotFound, "Document match #{_id.inspect} does not exist in #{collection.name} collection"
      end
    end

  end
end


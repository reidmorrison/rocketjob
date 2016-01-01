# encoding: UTF-8
require 'socket'
require 'concurrent'
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
    include Plugins::Document
    include Plugins::StateMachine
    include SemanticLogger::Loggable

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

    # Requeue any jobs being worked by this worker when it is destroyed
    before_destroy :requeue_jobs

    after_initialize :build_heartbeat

    # Run the worker process
    # Attributes supplied are passed to #new
    def self.run(attrs={})
      Thread.current.name = 'rocketjob main'
      create_indexes
      register_signal_handlers
      if defined?(RocketJobPro) && (RocketJob::Job.database.name != RocketJob::Jobs::PerformanceJob.database.name)
        raise 'The RocketJob configuration is being applied after the system has been initialized'
      end

      worker = create!(attrs)
      if worker.max_threads == 0
        # Does not start any additional threads and runs the worker in the current thread.
        # No heartbeats are performed. So this worker will appear as a zombie in RJMC.
        # Designed for profiling purposes where a single thread is much simpler to profile.
        worker.started!
        worker.send(:worker, 0)
      else
        worker.send(:run)
      end

    ensure
      worker.destroy if worker
    end

    # Create indexes
    def self.create_indexes
      ensure_index [[:name, 1]], background: true, unique: true
      # Also create indexes for the jobs collection
      Job.create_indexes
    end

    # Destroy's all instances of zombie workers and requeues any jobs still "running"
    # on those workers
    def self.destroy_zombies
      count = 0
      each do |worker|
        next unless worker.zombie?
        logger.warn "Destroying zombie worker #{worker.name}, and requeueing its jobs"
        worker.destroy
        count += 1
      end
      count
    end

    # Stop all running, paused, or starting workers
    def self.stop_all
      where(state: [:running, :paused, :starting]).each(&:stop!)
    end

    # Pause all running workers
    def self.pause_all
      running.each(&:pause!)
    end

    # Resume all paused workers
    def self.resume_all
      paused.each(&:resume!)
    end

    # Returns [Boolean] whether the worker is shutting down
    def shutting_down?
      self.class.shutdown? || !running?
    end

    # Returns [true|false] if this worker has missed at least the last 4 heartbeats
    #
    # Possible causes for a worker to miss its heartbeats:
    # - The worker process has died
    # - The worker process is "hanging"
    # - The worker is no longer able to communicate with the MongoDB Server
    def zombie?(missed = 4)
      return false unless running?
      dead_seconds = Config.instance.heartbeat_seconds * missed
      (Time.now - heartbeat.updated_at) >= dead_seconds
    end

    # On MRI the 'concurrent-ruby-ext' gem may not be loaded
    if defined?(Concurrent::JavaAtomicBoolean) || defined?(Concurrent::CAtomicBoolean)
      # Returns [true|false] whether the shutdown indicator has been set for this worker process
      def self.shutdown?
        @@shutdown.value
      end

      # Set shutdown indicator for this worker process
      def self.shutdown!
        @@shutdown.make_true
      end

      @@shutdown = Concurrent::AtomicBoolean.new(false)
    else
      # Returns [true|false] whether the shutdown indicator has been set for this worker process
      def self.shutdown?
        @@shutdown
      end

      # Set shutdown indicator for this worker process
      def self.shutdown!
        @@shutdown = true
      end

      @@shutdown = false
    end

    private

    attr_reader :worker_threads

    # Returns [Array<Thread>] collection of created worker threads
    def worker_threads
      @worker_threads ||= []
    end

    # Management Thread
    def run
      logger.info "Using MongoDB Database: #{RocketJob::Job.database.name}"
      started!
      adjust_worker_threads(true)
      logger.info "RocketJob Worker started with #{max_threads} workers running"

      count = 0
      while running? || paused?
        sleep Config.instance.heartbeat_seconds

        update_attributes_and_reload(
          'heartbeat.updated_at'      => Time.now,
          'heartbeat.current_threads' => worker_count
        )

        # In case number of threads has been modified
        adjust_worker_threads

        # Stop worker if shutdown indicator was set
        stop! if self.class.shutdown? && may_stop?
      end
      logger.info 'Waiting for worker threads to stop'
      # TODO Put a timeout on join.
      # Log Thread dump for active threads
      # Compare thread dumps for any changes, force down if no change?
      # reload, if model missing: Send Shutdown exception to each thread
      #           5 more seconds then exit
      worker_threads.each { |t| t.join }
      logger.info 'Shutdown'
    rescue Exception => exc
      logger.error('RocketJob::Worker is stopping due to an exception', exc)
    end

    # Returns [Fixnum] number of workers (threads) that are alive
    def worker_count
      worker_threads.count { |i| i.alive? }
    end

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
    def adjust_worker_threads(stagger_threads=false)
      count = worker_count
      # Cleanup threads that have stopped
      if count != worker_threads.count
        logger.info "Cleaning up #{worker_threads.count - count} threads that went away"
        worker_threads.delete_if { |t| !t.alive? }
      end

      return if shutting_down?

      # Need to add more threads?
      if count < max_threads
        thread_count = max_threads - count
        logger.info "Starting #{thread_count} threads"
        thread_count.times.each do
          # Start worker thread
          worker_threads << Thread.new(next_worker_id) do |id|
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
      Thread.current.name = 'rocketjob %03i' % worker_id
      logger.info 'Started'
      while !shutting_down?
        if process_available_jobs
          # Keeps workers staggered across the poll interval so that
          # all workers don't poll at the same time
          sleep rand(RocketJob::Config.instance.max_poll_seconds * 1000) / 1000
        else
          break if shutting_down?
          sleep RocketJob::Config.instance.max_poll_seconds
        end
      end
      logger.info "Stopping. Worker state: #{state.inspect}"
    rescue Exception => exc
      logger.fatal('Unhandled exception in job processing thread', exc)
    end

    # Process the next available job
    # Returns [Boolean] whether any job was actually processed
    def process_available_jobs
      skip_job_ids = []
      processed    = false
      while (job = Job.rocket_job_next_job(name, skip_job_ids)) && !shutting_down?
        logger.fast_tag("Job #{job.id}") do
          if job.work(self)
            # Need to skip the specified job due to throttling or no work available
            skip_job_ids << job.id
          else
            processed = true
          end
        end
      end
      processed
    end

    # Register handlers for the various signals
    # Term:
    #   Perform clean shutdown
    #
    def self.register_signal_handlers
      begin
        Signal.trap 'SIGTERM' do
          shutdown!
          message = 'Shutdown signal (SIGTERM) received. Will shutdown as soon as active jobs/slices have completed.'
          # Logging uses a mutex to access Queue on MRI/CRuby
          defined?(JRuby) ? logger.warn(message) : puts(message)
        end

        Signal.trap 'INT' do
          shutdown!
          message = 'Shutdown signal (INT) received. Will shutdown as soon as active jobs/slices have completed.'
          # Logging uses a mutex to access Queue on MRI/CRuby
          defined?(JRuby) ? logger.warn(message) : puts(message)
        end
      rescue StandardError
        logger.warn 'SIGTERM handler not installed. Not able to shutdown gracefully'
      end
    end

    # Requeue any jobs assigned to this worker when it is destroyed
    def requeue_jobs
      RocketJob::Job.requeue_dead_worker(name)
    end

  end
end


require 'yaml'
require 'concurrent'
module RocketJob
  # Server
  #
  # On startup a server instance will automatically register itself
  # if not already present
  #
  # Starting a server in the foreground:
  #   - Using a Rails runner:
  #     bin/rocketjob
  #
  # Starting a server in the background:
  #   - Using a Rails runner:
  #     nohup bin/rocketjob --quiet 2>&1 1>output.log &
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
  class Server
    include Plugins::Document
    include Plugins::StateMachine
    include SemanticLogger::Loggable

    store_in collection: 'rocket_job.servers'

    # Unique Name of this server instance
    #   Default: `host name:PID`
    # The unique name is used on re-start to re-queue any jobs that were being processed
    # at the time the server unexpectedly terminated, if any
    field :name, type: String, default: -> { "#{SemanticLogger.host}:#{$$}" }

    # The maximum number of workers this server should start
    #   If set, it will override the default value in RocketJob::Config
    field :max_workers, type: Integer, default: -> { Config.instance.max_workers }

    # When this server process was started
    field :started_at, type: Time

    # Filter to apply to control which job classes this server can process
    field :yaml_filter, type: String

    # The heartbeat information for this server
    embeds_one :heartbeat, class_name: 'RocketJob::Heartbeat'

    # Current state
    #   Internal use only. Do not set this field directly
    field :state, type: Symbol, default: :starting

    index({name: 1}, background: true, unique: true, drop_dups: true)

    validates_presence_of :state, :name, :max_workers

    # States
    #   :starting -> :running -> :paused
    #                         -> :stopping
    aasm column: :state, whiny_persistence: true do
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
        transitions from: :running, to: :stopping
        transitions from: :paused, to: :stopping
        transitions from: :starting, to: :stopping
      end
    end

    # Requeue any jobs being worked by this server when it is destroyed
    before_destroy :requeue_jobs

    # Destroy's all instances of zombie servers and requeues any jobs still "running"
    # on those servers.
    def self.destroy_zombies
      count = 0
      each do |server|
        next unless server.zombie?
        logger.warn "Destroying zombie server #{server.name}, and requeueing its jobs"
        server.destroy
        count += 1
      end
      count
    end

    # Stop all running, paused, or starting servers
    def self.stop_all
      where(:state.in => %i[running paused starting]).each(&:stop!)
    end

    # Pause all running servers
    def self.pause_all
      running.each(&:pause!)
    end

    # Resume all paused servers
    def self.resume_all
      paused.each(&:resume!)
    end

    # Returns [Hash<String:Integer>] of the number of servers in each state.
    # Note: If there are no servers in that particular state then the hash will not have a value for it.
    #
    # Example servers in every state:
    #   RocketJob::Server.counts_by_state
    #   # => {
    #          :aborted => 1,
    #          :completed => 37,
    #          :failed => 1,
    #          :paused => 3,
    #          :queued => 4,
    #          :running => 1,
    #          :queued_now => 1,
    #          :scheduled => 3
    #        }
    #
    # Example no servers active:
    #   RocketJob::Server.counts_by_state
    #   # => {}
    def self.counts_by_state
      counts = {}
      collection.aggregate(
        [
          {
            '$group' => {
              _id:   '$state',
              count: {'$sum' => 1}
            }
          }
        ]
      ).each do |result|
        counts[result['_id'].to_sym] = result['count']
      end
      counts
    end

    # On MRI the 'concurrent-ruby-ext' gem may not be loaded
    if defined?(Concurrent::JavaAtomicBoolean) || defined?(Concurrent::CAtomicBoolean)
      # Returns [true|false] whether the shutdown indicator has been set for this server process
      def self.shutdown?
        @shutdown.value
      end

      # Set shutdown indicator for this server process
      def self.shutdown!
        @shutdown.make_true
      end

      @shutdown = Concurrent::AtomicBoolean.new(false)
    else
      # Returns [true|false] whether the shutdown indicator has been set for this server process
      def self.shutdown?
        @shutdown
      end

      # Set shutdown indicator for this server process
      def self.shutdown!
        @shutdown = true
      end

      @shutdown = false
    end

    # Run the server process
    # Attributes supplied are passed to #new
    def self.run(attrs = {})
      Thread.current.name = 'rocketjob main'
      # Create Indexes on server startup
      Mongoid::Tasks::Database.create_indexes
      register_signal_handlers

      server = create!(attrs)
      server.send(:run)
    ensure
      server&.destroy
    end

    # Returns [Boolean] whether the server is shutting down
    def shutdown?
      self.class.shutdown? || !running?
    end

    # Scope for all zombie servers
    def self.zombies(missed = 4)
      dead_seconds        = Config.instance.heartbeat_seconds * missed
      last_heartbeat_time = Time.now - dead_seconds
      where(
        :state.in => %i[stopping running paused],
        '$or'     => [
          {'heartbeat.updated_at' => {'$exists' => false}},
          {'heartbeat.updated_at' => {'$lte' => last_heartbeat_time}}
        ]
      )
    end

    # Returns [true|false] if this server has missed at least the last 4 heartbeats
    #
    # Possible causes for a server to miss its heartbeats:
    # - The server process has died
    # - The server process is "hanging"
    # - The server is no longer able to communicate with the MongoDB Server
    def zombie?(missed = 4)
      return false unless running? || stopping? || paused?
      return true if heartbeat.nil? || heartbeat.updated_at.nil?
      dead_seconds = Config.instance.heartbeat_seconds * missed
      (Time.now - heartbeat.updated_at) >= dead_seconds
    end

    # Where clause filter to apply to workers looking for jobs
    def filter
      YAML.load(yaml_filter)
    end

    def filter=(hash)
      self.yaml_filter = hash.nil? ? nil : hash.to_yaml
    end

    private

    # Returns [Array<Worker>] collection of workers
    def workers
      @workers ||= []
    end

    # Management Thread
    def run
      logger.info "Using MongoDB Database: #{RocketJob::Job.collection.database.name}"
      logger.info('Running with filter', filter) if filter
      build_heartbeat(updated_at: Time.now, workers: 0)
      started!
      logger.info 'Rocket Job Server started'

      run_workers

      logger.info 'Waiting for workers to stop'
      # Tell each worker to shutdown cleanly
      workers.each(&:shutdown!)

      while (worker = workers.first)
        if worker.join(5)
          # Worker thread is dead
          workers.shift
        else
          # Timeout waiting for worker to stop
          find_and_update(
            'heartbeat.updated_at' => Time.now,
            'heartbeat.workers'    => worker_count
          )
        end
      end

      logger.info 'Shutdown'
    rescue Mongoid::Errors::DocumentNotFound
      logger.warn('Server has been destroyed. Going down hard!')
    rescue Exception => exc
      logger.error('RocketJob::Server is stopping due to an exception', exc)
    ensure
      # Logs the backtrace for each running worker
      workers.each { |worker| logger.backtrace(thread: worker.thread) if worker.thread && worker.alive? }
    end

    def run_workers
      stagger = true
      while running? || paused?
        SemanticLogger.silence(:info) do
          find_and_update(
            'heartbeat.updated_at' => Time.now,
            'heartbeat.workers'    => worker_count
          )
        end
        if paused?
          workers.each(&:shutdown!)
          stagger = true
        end

        # In case number of threads has been modified
        adjust_workers(stagger)
        stagger = false

        # Stop server if shutdown indicator was set
        if self.class.shutdown? && may_stop?
          stop!
        else
          sleep Config.instance.heartbeat_seconds
        end
      end
    end

    # Returns [Fixnum] number of workers (threads) that are alive
    def worker_count
      workers.count(&:alive?)
    end

    def next_worker_id
      @worker_id ||= 0
      @worker_id += 1
    end

    # Re-adjust the number of running workers to get it up to the
    # required number of workers
    #   Parameters
    #     stagger_workers
    #       Whether to stagger when the workers poll for work the first time
    #       It spreads out the queue polling over the max_poll_seconds so
    #       that not all workers poll at the same time
    #       The worker also respond faster than max_poll_seconds when a new
    #       job is added.
    def adjust_workers(stagger_workers = false)
      count = worker_count
      # Cleanup workers that have stopped
      if count != workers.count
        logger.info "Cleaning up #{workers.count - count} workers that went away"
        workers.delete_if { |t| !t.alive? }
      end

      return unless running?

      # Need to add more workers?
      return unless count < max_workers

      worker_count = max_workers - count
      logger.info "Starting #{worker_count} workers"
      worker_count.times.each do
        sleep(Config.instance.max_poll_seconds.to_f / max_workers) if stagger_workers
        return if shutdown?
        # Start worker
        begin
          workers << Worker.new(id: next_worker_id, server_name: name, filter: filter)
        rescue Exception => exc
          logger.fatal('Cannot start worker', exc)
        end
      end
    end

    # Register handlers for the various signals
    # Term:
    #   Perform clean shutdown
    #
    def self.register_signal_handlers
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

    private_class_method :register_signal_handlers

    # Requeue any jobs assigned to this server when it is destroyed
    def requeue_jobs
      RocketJob::Job.requeue_dead_server(name)
    end
  end
end

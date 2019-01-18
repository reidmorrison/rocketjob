require 'rocket_job/supervisor/shutdown'

module RocketJob
  # Starts a server instance, along with the workers and ensures workers remain running until they need to shutdown.
  class Supervisor
    include SemanticLogger::Loggable
    include Supervisor::Shutdown

    attr_reader :server, :workers
    attr_accessor :worker_id

    def self.create_indexes
      # Ensure models with indexes are loaded into memory first
      Job
      Server
      DirmonEntry
      ::Mongoid::Tasks::Database.create_indexes
    end

    # Start the Supervisor, using the supplied attributes to create a new Server instance.
    def self.run(attrs = {})
      Thread.current.name = 'rocketjob main'
      create_indexes
      register_signal_handlers

      server = Server.create!(attrs)
      new(server).run
    ensure
      server&.destroy
    end

    def initialize(server)
      @server    = server
      @workers   = []
      @worker_id = 0
    end

    def run
      logger.info "Using MongoDB Database: #{RocketJob::Job.collection.database.name}"
      logger.info('Running with filter', server.filter) if server.filter
      server.started!
      logger.info 'Rocket Job Server started'

      run_workers
      server.stop! if server.may_stop?
      shutdown_workers

      logger.info 'Shutdown'
    rescue ::Mongoid::Errors::DocumentNotFound
      logger.warn('Server has been destroyed. Going down hard!')
    rescue Exception => exc
      logger.error('RocketJob::Server is stopping due to an exception', exc)
    ensure
      # Logs the backtrace for each running worker
      workers.each { |worker| logger.backtrace(thread: worker.thread) if worker.thread && worker.alive? }
    end

    def run_workers
      stagger = true
      while !self.class.shutdown? && (server.running? || server.paused?)
        if server.paused?
          workers.each(&:shutdown!)
          stagger = true
        end

        remove_dead_workers
        if server.running?
          add_workers(stagger)
          stagger = false
        end

        sleep Config.instance.heartbeat_seconds

        server.refresh(living_worker_count)
      end
    end

    def shutdown_workers
      logger.info 'Waiting for workers to stop'
      # Tell each worker to shutdown cleanly
      workers.each(&:shutdown!)

      while (worker = workers.first)
        if worker.join(5)
          # Worker thread is dead
          workers.shift
        else
          # Worker still running so update heartbeat so that server reports "alive".
          server.refresh(living_worker_count)
        end
      end
    end

    # Returns [Fixnum] number of workers (threads) that are alive
    def living_worker_count
      workers.count(&:alive?)
    end

    def next_worker_id
      @worker_id += 1
    end

    # Add new workers to get back to the `max_workers` if not already at `max_workers`
    #   Parameters
    #     stagger_workers
    #       Whether to stagger when the workers poll for work the first time.
    #       It spreads out the queue polling over the max_poll_seconds so
    #       that not all workers poll at the same time.
    #       The worker also responds faster than max_poll_seconds when a new job is added.
    def add_workers(stagger_workers = false)
      add_worker_count = server.max_workers - living_worker_count
      return 0 if add_worker_count.zero?

      logger.info "Starting #{add_worker_count} workers"
      add_worker_count.times.each do
        sleep(Config.instance.max_poll_seconds.to_f / server.max_workers) if stagger_workers
        return -1 if self.class.shutdown?
        start_worker
      end
    end

    # Returns [Integer] number of dead workers removed.
    def remove_dead_workers
      remove_count = workers.count - living_worker_count
      return 0 if remove_count.zero?

      logger.info "Cleaning up #{workers.count - count} workers that went away"
      workers.delete_if { |t| !t.alive? }
      remove_count
    end

    def start_worker
      workers << Worker.new(id: next_worker_id, server_name: server.name, filter: server.filter)
    rescue StandardError => exc
      logger.fatal('Cannot start worker', exc)
    end

  end
end

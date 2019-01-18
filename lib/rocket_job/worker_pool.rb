require 'rocket_job/supervisor/shutdown'

module RocketJob
  class WorkerPool
    include SemanticLogger::Loggable

    attr_reader :server, :workers

    def initialize(server)
      @server    = server
      @workers   = []
      @worker_id = 0
    end

    # Add new workers to get back to the `max_workers` if not already at `max_workers`
    #   Parameters
    #     stagger_start
    #       Whether to stagger when the workers poll for work the first time.
    #       It spreads out the queue polling over the max_poll_seconds so
    #       that not all workers poll at the same time.
    #       The worker also responds faster than max_poll_seconds when a new job is created.
    def rebalance(stagger_start = false)
      count = server.max_workers.to_i - living_count
      return 0 unless count > 0

      logger.info "Starting #{count} workers"

      add_one
      count -= 1
      delay = Config.instance.max_poll_seconds.to_f / server.max_workers

      count.times.each do
        sleep(delay) if stagger_start
        return -1 if Supervisor.shutdown?
        add_one
      end
    end

    # Returns [Integer] number of dead workers removed.
    def prune
      remove_count = workers.count - living_count
      return 0 if remove_count.zero?

      logger.info "Cleaned up #{workers.count - count} dead workers"
      workers.delete_if { |t| !t.alive? }
      remove_count
    end

    # Tell all workers to stop working.
    def stop!
      workers.each(&:shutdown!)
    end

    # Shutdown and wait for all workers to stop.
    def shutdown!
      stop!

      logger.info 'Waiting for workers to stop'
      while (worker = workers.first)
        if worker.join(5)
          # Worker thread is dead
          workers.shift
        else
          # Worker still running so update heartbeat so that server reports "alive".
          server.refresh(living_count)
        end
      end
    end

    # Returns [Fixnum] number of workers (threads) that are alive
    def living_count
      workers.count(&:alive?)
    end

    def log_bracktraces
      workers.each { |worker| logger.backtrace(thread: worker.thread) if worker.thread && worker.alive? }
    end

    private

    def add_one
      workers << Worker.new(id: next_worker_id, server_name: server.name, filter: server.filter)
    rescue StandardError => exc
      logger.fatal('Cannot start worker', exc)
    end

    def next_worker_id
      @worker_id += 1
    end

  end
end

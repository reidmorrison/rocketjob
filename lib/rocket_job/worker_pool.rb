require "concurrent-ruby"
require "rocket_job/supervisor/shutdown"

module RocketJob
  class WorkerPool
    include SemanticLogger::Loggable

    attr_reader :server_name, :workers

    def initialize(server_name)
      @server_name = server_name
      @workers     = Concurrent::Array.new
      @worker_id   = 0
    end

    # Find a worker in the list by its id
    def find(id)
      workers.find { |worker| worker.id == id }
    end

    # Add new workers to get back to the `max_workers` if not already at `max_workers`
    #   Parameters
    #     stagger_start
    #       Whether to stagger when the workers poll for work the first time.
    #       It spreads out the queue polling over the max_poll_seconds so
    #       that not all workers poll at the same time.
    #       The worker also responds faster than max_poll_seconds when a new job is created.
    def rebalance(max_workers, stagger_start = false)
      count = max_workers.to_i - living_count
      return 0 unless count.positive?

      logger.info("#{'Stagger ' if stagger_start}Starting #{count} workers")

      add_one
      count -= 1
      delay = Config.max_poll_seconds.to_f / max_workers

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

      logger.info "Cleaned up #{remove_count} dead workers"
      workers.delete_if { |t| !t.alive? }
      remove_count
    end

    # Tell all workers to stop working.
    def stop
      workers.each(&:shutdown!)
    end

    # Kill Worker threads
    def kill
      workers.each(&:kill)
    end

    # Wait for all workers to stop.
    # Return [true] if all workers stopped
    # Return [false] on timeout
    def join(timeout = 5)
      while (worker = workers.first)
        if worker.join(timeout)
          # Worker thread is dead
          workers.shift
        else
          return false
        end
      end
      true
    end

    # Returns [Integer] number of workers (threads) that are alive
    def living_count
      workers.count(&:alive?)
    end

    def log_backtraces
      workers.each { |worker| logger.backtrace(thread: worker.thread) if worker.thread && worker.alive? }
    end

    private

    def add_one
      workers << Worker.new(id: next_worker_id, server_name: server_name)
    rescue StandardError => e
      logger.fatal("Cannot start worker", e)
    end

    def next_worker_id
      @worker_id += 1
    end
  end
end

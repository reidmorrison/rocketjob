require 'rocket_job/supervisor/shutdown'

module RocketJob
  # Starts a server instance, along with the workers and ensures workers remain running until they need to shutdown.
  class Supervisor
    include SemanticLogger::Loggable
    include Supervisor::Shutdown

    attr_reader :server, :worker_pool
    attr_accessor :worker_id

    # Start the Supervisor, using the supplied attributes to create a new Server instance.
    def self.run(attrs = {})
      Thread.current.name = 'rocketjob main'
      RocketJob.create_indexes
      register_signal_handlers

      server = Server.create!(attrs)
      new(server).run
    ensure
      server&.destroy
    end

    def initialize(server)
      @server      = server
      @worker_pool = WorkerPool.new(server)
    end

    def run
      logger.info "Using MongoDB Database: #{RocketJob::Job.collection.database.name}"
      logger.info('Running with filter', server.filter) if server.filter
      server.started!
      logger.info 'Rocket Job Server started'

      supervise_pool

      server.stop! if server.may_stop?
      worker_pool.shutdown!

      logger.info 'Shutdown Complete'
    rescue ::Mongoid::Errors::DocumentNotFound
      logger.warn('Server has been destroyed. Going down hard!')
    rescue Exception => exc
      logger.error('RocketJob::Server is stopping due to an exception', exc)
    ensure
      # Logs the backtrace for each running worker
      worker_pool.log_bracktraces
    end

    def supervise_pool
      stagger = true
      while !self.class.shutdown? && (server.running? || server.paused?)
        if server.paused?
          worker_pool.stop!
          stagger = true
        end

        worker_pool.prune

        if server.running?
          worker_pool.rebalance(stagger)
          stagger = false
        end

        break if self.class.wait_for_shutdown?(Config.instance.heartbeat_seconds)

        server.refresh(worker_pool.living_count)
      end
    end
  end
end

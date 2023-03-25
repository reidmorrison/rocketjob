require "rocket_job/supervisor/shutdown"

module RocketJob
  # Starts a server instance, along with the workers and ensures workers remain running until they need to shutdown.
  class Supervisor
    include SemanticLogger::Loggable
    include Supervisor::Shutdown

    attr_reader :server, :worker_pool

    # Start the Supervisor, using the supplied attributes to create a new Server instance.
    def self.run
      Thread.current.name = "rocketjob main"
      RocketJob.create_indexes
      register_signal_handlers

      server = Server.create!
      new(server).run
    ensure
      server&.destroy
    end

    def initialize(server)
      @server      = server
      @worker_pool = WorkerPool.new(server.name)
      @mutex       = Mutex.new
    end

    def run
      logger.info "Using MongoDB Database: #{RocketJob::Job.collection.database.name}"
      logger.info("Running with filter", Config.filter) if Config.filter
      server.started!
      logger.info "Rocket Job Server started"

      event_listener = Thread.new { Event.listener }
      Subscribers::SecretConfig.subscribe if defined?(SecretConfig)
      Subscribers::Server.subscribe(self) do
        Subscribers::Worker.subscribe(self) do
          Subscribers::Logger.subscribe do
            supervise_pool
            stop
          end
        end
      end
    rescue ::Mongoid::Errors::DocumentNotFound
      logger.info("Server has been destroyed. Going down hard!")
    rescue Exception => e
      logger.error("RocketJob::Server is stopping due to an exception", e)
    ensure
      event_listener&.kill
      # Logs the backtrace for each running worker
      worker_pool.log_backtraces
      logger.info("Shutdown Complete")
    end

    def stop
      server.stop! if server.may_stop?
      synchronize do
        worker_pool.stop
      end
      until worker_pool.join
        logger.info "Waiting for workers to finish processing ..."
        # One or more workers still running so update heartbeat so that server reports "alive".
        server.refresh(worker_pool.living_count)
      end
    end

    def kill
      synchronize do
        self.class.shutdown!

        logger.info("Stopping Pool")
        worker_pool.stop
        unless worker_pool.living_count.zero?
          logger.info("Giving pool #{wait_timeout} seconds to terminate")
          sleep(wait_timeout)
        end
        logger.info("Kill Pool")
        worker_pool.kill
      end
    end

    def pause
      synchronize { server.pause! if server.may_pause? }
      self.class.event!
    end

    def resume
      synchronize { server.resume! if server.may_resume? }
      self.class.event!
    end

    def thread_dump
      worker_pool.log_backtraces
    end

    def synchronize(&block)
      @mutex.synchronize(&block)
    end

    private

    def supervise_pool
      stagger = true
      until self.class.shutdown?
        synchronize do
          if server.running?
            worker_pool.prune
            worker_pool.rebalance(server.max_workers, stagger)
            stagger = false
          elsif server.paused?
            worker_pool.stop
            sleep(0.1)
            worker_pool.prune
            stagger = true
          else
            break
          end
        end

        synchronize { server.refresh(worker_pool.living_count) }

        self.class.wait_for_event(Config.heartbeat_seconds)

        break if self.class.shutdown?
      end
    end
  end
end

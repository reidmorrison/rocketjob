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
            stop!
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

    def stop!
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

    def synchronize(&)
      @mutex.synchronize(&)
    end

    # Returns [true|false] whether the server of this supervisor is the one with the supplied id or name, which an
    # event names to act on that server only. An event that names neither acts on every server. The id is compared as
    # text, so that an id published as a String matches too.
    def server?(server_id: nil, name: nil)
      return true if server_id.nil? && name.nil?

      server.name == name || server_id.to_s == server.id.to_s
    end

    # Shuts down this server, stopping its workers, giving those still working `wait_timeout` seconds to finish,
    # then killing them.
    def kill(wait_timeout = 5)
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

    # Pauses this server, which stops its workers until it is resumed, see #resume.
    def pause
      synchronize { server.pause! if server.may_pause? }
      self.class.event!
    end

    # Resumes this server after it was paused, see #pause.
    def resume
      synchronize { server.resume! if server.may_resume? }
      self.class.event!
    end

    # Logs the backtrace of each of the workers of this server.
    def log_backtraces
      worker_pool.log_backtraces
    end

    # Returns [RocketJob::ThreadWorker] the worker of this server with the supplied id, or nil when it has none that is
    # alive.
    def worker(worker_id)
      return unless worker_id

      worker = worker_pool.find(worker_id)
      worker if worker&.alive?
    end
  end
end

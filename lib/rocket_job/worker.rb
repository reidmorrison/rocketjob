require 'concurrent'
require 'forwardable'
module RocketJob
  # Worker
  #
  # A worker runs on a single operating system thread
  # Is usually started under a Rocket Job server process.
  class Worker
    include SemanticLogger::Loggable
    include ActiveSupport::Callbacks

    define_callbacks :running

    attr_accessor :id, :current_filter
    attr_reader :thread, :name, :inline

    # Raised when a worker is killed so that it shutdown immediately, yet cleanly.
    #
    # Note:
    # - It is not recommended to catch this exception since it is to shutdown workers quickly.
    class Shutdown < Interrupt
    end

    def self.before_running(*filters, &blk)
      set_callback(:running, :before, *filters, &blk)
    end

    def self.after_running(*filters, &blk)
      set_callback(:running, :after, *filters, &blk)
    end

    def self.around_running(*filters, &blk)
      set_callback(:running, :around, *filters, &blk)
    end

    def initialize(id: 0, server_name: 'inline:0', inline: false)
      @id             = id
      @server_name    = server_name
      @shutdown       = Concurrent::Event.new
      @name           = "#{server_name}:#{id}"
      @re_check_start = Time.now
      @current_filter = Config.filter || {}
      @thread         = Thread.new { run } unless inline
      @inline         = inline
    end

    def alive?
      inline ? true : @thread.alive?
    end

    def backtrace
      inline ? Thread.current.backtrace : @thread.backtrace
    end

    def join(*args)
      @thread.join(*args) unless inline
    end

    # Send each active worker the RocketJob::ShutdownException so that stops processing immediately.
    def kill
      return true if inline

      @thread.raise(Shutdown, "Shutdown due to kill request for worker: #{name}") if @thread.alive?
    end

    def shutdown?
      @shutdown.set?
    end

    def shutdown!
      @shutdown.set
    end

    # Returns [true|false] whether the shutdown indicator was set
    def wait_for_shutdown?(timeout = nil)
      @shutdown.wait(timeout)
    end

    private

    # Process jobs until it shuts down
    #
    # Params
    #   worker_id [Integer]
    #     The number of this worker for logging purposes
    def run
      Thread.current.name = format('rocketjob %03i', id)
      logger.info 'Started'
      until shutdown?
        wait = Config.max_poll_seconds
        if process_available_jobs
          # Keeps workers staggered across the poll interval so that
          # all workers don't poll at the same time
          wait = rand(wait * 1000) / 1000
        end
        break if wait_for_shutdown?(wait)
      end
      logger.info 'Stopping'
    rescue Exception => exc
      logger.fatal('Unhandled exception in job processing thread', exc)
    ensure
      ActiveRecord::Base.clear_active_connections! if defined?(ActiveRecord::Base)
    end

    # Process the next available job
    # Returns [Boolean] whether any job was actually processed
    def process_available_jobs
      processed = false
      until shutdown?
        reset_filter_if_expired
        job = Job.rocket_job_next_job(name, current_filter)
        break unless job

        SemanticLogger.named_tagged(job: job.id.to_s) do
          processed = true unless job.rocket_job_work(self, false, current_filter)

          # Return the database connections for this thread back to the connection pool
          ActiveRecord::Base.clear_active_connections! if defined?(ActiveRecord::Base)
        end
      end
      processed
    end

    # Resets the current job filter if the relevant time interval has passed
    def reset_filter_if_expired
      # Only clear out the current_filter after every `re_check_seconds`
      time = Time.now
      return unless (time - @re_check_start) > Config.re_check_seconds

      @re_check_start     = time
      self.current_filter = Config.filter || {}
    end
  end
end

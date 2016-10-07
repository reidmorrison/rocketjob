# encoding: UTF-8
require 'concurrent'
require 'forwardable'
module RocketJob
  # Worker
  #
  # A worker runs on a single operating system thread
  # Is usually started under a RocketJob server process.
  class Worker
    include SemanticLogger::Loggable
    include ActiveSupport::Callbacks
    extend Forwardable

    def_delegator :@thread, :alive?
    def_delegator :@thread, :backtrace
    def_delegator :@thread, :join

    define_callbacks :running

    attr_accessor :id, :worker_name
    attr_reader :thread, :name

    def self.before_running(*filters, &blk)
      set_callback(:running, :before, *filters, &blk)
    end

    def self.after_running(*filters, &blk)
      set_callback(:running, :after, *filters, &blk)
    end

    def self.around_running(*filters, &blk)
      set_callback(:running, :around, *filters, &blk)
    end

    def initialize(id, server_name)
      @id          = id
      @server_name = server_name
      if defined?(Concurrent::JavaAtomicBoolean) || defined?(Concurrent::CAtomicBoolean)
        @shutdown = Concurrent::AtomicBoolean.new(false)
      else
        @shutdown = false
      end
      @name   = "#{server_name}:%04i" % id
      @thread = Thread.new { run }
    end

    if defined?(Concurrent::JavaAtomicBoolean) || defined?(Concurrent::CAtomicBoolean)
      # Tells this worker to shutdown as soon the current job/slice is complete
      def shutdown!
        @shutdown.make_true
      end

      def shutdown?
        @shutdown.value
      end
    else
      def shutdown!
        @shutdown = true
      end

      def shutdown?
        @shutdown
      end
    end

    private

    # Process jobs until it shuts down
    #
    # Params
    #   worker_id [Integer]
    #     The number of this worker for logging purposes
    def run
      Thread.current.name = 'rocketjob %03i' % id
      logger.info 'Started'
      while !shutdown?
        if process_available_jobs
          # Keeps workers staggered across the poll interval so that
          # all workers don't poll at the same time
          sleep rand(RocketJob::Config.instance.max_poll_seconds * 1000) / 1000
        else
          break if shutdown?
          sleep RocketJob::Config.instance.max_poll_seconds
        end
      end
      logger.info 'Stopping'
    rescue Exception => exc
      logger.fatal('Unhandled exception in job processing thread', exc)
    ensure
      # TODO: Move to after_running callback
      ActiveRecord::Base.clear_active_connections! if defined?(ActiveRecord::Base)
    end

    # Process the next available job
    # Returns [Boolean] whether any job was actually processed
    def process_available_jobs
      skip_job_ids = []
      processed    = false
      while (job = Job.rocket_job_next_job(worker_name, skip_job_ids)) && !shutdown?
        logger.fast_tag("job:#{job.id}") do
          if job.rocket_job_work(self)
            # Need to skip the specified job due to throttling or no work available
            skip_job_ids << job.id
          else
            processed = true
          end
        end
      end
      processed
    end

  end
end


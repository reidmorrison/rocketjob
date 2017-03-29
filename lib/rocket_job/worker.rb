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

    attr_accessor :id, :re_check_seconds, :filter, :current_filter
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

    def initialize(id: 0, server_name: 'inline:0', inline: false, re_check_seconds: Config.instance.re_check_seconds, filter: nil)
      @id          = id
      @server_name = server_name
      if defined?(Concurrent::JavaAtomicBoolean) || defined?(Concurrent::CAtomicBoolean)
        @shutdown = Concurrent::AtomicBoolean.new(false)
      else
        @shutdown = false
      end
      @name             = "#{server_name}:#{id}"
      @re_check_seconds = (re_check_seconds || 60).to_f
      @re_check_start   = Time.now
      @filter           = filter || {}
      @current_filter   = @filter.dup
      @thread           = Thread.new { run } unless inline
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
      ActiveRecord::Base.clear_active_connections! if defined?(ActiveRecord::Base)
    end

    # Process the next available job
    # Returns [Boolean] whether any job was actually processed
    def process_available_jobs
      processed = false
      while !shutdown?
        reset_filter_if_expired
        job = Job.rocket_job_next_job(name, current_filter)
        break unless job

        SemanticLogger.named_tagged(job: job.id.to_s) do
          unless job.rocket_job_work(self, false, current_filter)
            processed = true
          end
        end
      end
      processed
    end

    # Resets the current job filter if the relevant time interval has passed
    def reset_filter_if_expired
      # Only clear out the current_filter after every `re_check_seconds`
      time = Time.now
      if (time - @re_check_start) > re_check_seconds
        @re_check_start     = time
        self.current_filter = filter.dup
      end
    end

  end
end


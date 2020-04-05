require "concurrent"
require "forwardable"
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
    attr_reader :thread, :name, :inline, :server_name

    # Raised when a worker is killed so that it shutdown immediately, yet cleanly.
    #
    # Note:
    # - It is not recommended to catch this exception since it is to shutdown workers quickly.
    class Shutdown < RuntimeError
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

    def initialize(id: 0, server_name: "inline:0", inline: false)
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

    # Process jobs until it shuts down
    #
    # Params
    #   worker_id [Integer]
    #     The number of this worker for logging purposes
    def run
      Thread.current.name = format("rocketjob %03i", id)
      logger.info "Started"

      until shutdown?
        sleep_seconds = Config.max_poll_seconds
        reset_filter_if_expired
        job = next_available_job

        # Returns true when work was completed, but no other work is available
        if job&.rocket_job_work(self, false)
          # Return the database connections for this thread back to the connection pool
          ActiveRecord::Base.clear_active_connections! if defined?(ActiveRecord::Base)

          # Stagger workers so that they don't all poll at the same time.
          sleep_seconds = random_wait_interval
        end

        wait_for_shutdown?(sleep_seconds)
      end

      logger.info "Stopping"
    rescue Exception => e
      logger.fatal("Unhandled exception in job processing thread", e)
    ensure
      ActiveRecord::Base.clear_active_connections! if defined?(ActiveRecord::Base)
    end

    # Resets the current job filter if the relevant time interval has passed
    def reset_filter_if_expired
      # Only clear out the current_filter after every `re_check_seconds`
      time = Time.now
      return unless (time - @re_check_start) > Config.re_check_seconds

      @re_check_start     = time
      self.current_filter = Config.filter || {}
    end

    # Returns [RocketJob::Job] the next job available for processing.
    # Returns [nil] if no job is available for processing.
    #
    # Notes:
    # - Destroys expired jobs
    # - Runs job throttles and skips the job if it is throttled.
    #   - Adding that filter to the current filter to exclude from subsequent polling.
    def next_available_job
      until shutdown?
        job = find_and_assign_job
        return unless job

        if job.expired?
          job.fail_on_exception! do
            job.worker_name = name
            job.destroy
            logger.info("Destroyed expired job.")
          end
          next
        end

        # Batch Job that is already started?
        # Batch has its own throttles for slices.
        return job if job.running?

        # Should this job be throttled?
        next if job.fail_on_exception! { throttled_job?(job) }

        # Start this job!
        job.fail_on_exception! { job.start!(name) }
        return job if job.running?
      end
    end

    # Whether the supplied job has been throttled and should be ignored.
    def throttled_job?(job)
      # Evaluate job throttles, if any.
      filter = job.rocket_job_throttles.matching_filter(job)
      return false unless filter

      add_to_current_filter(filter)
      # Restore retrieved job so that other workers can process it later
      job.set(worker_name: nil, state: :queued)
      true
    end

    # Finds the next job to work on in priority based order
    # and assigns it to this worker.
    #
    # Applies the current filter to exclude filtered jobs.
    #
    # Returns nil if no jobs are available for processing.
    if Mongoid::VERSION.to_f >= 7.1
      def find_and_assign_job
        SemanticLogger.silence(:info) do
          scheduled = RocketJob::Job.where(run_at: nil).or(:run_at.lte => Time.now)
          working   = RocketJob::Job.queued.or(state: :running, sub_state: :processing)
          query     = RocketJob::Job.and(working, scheduled)
          query     = query.and(current_filter) unless current_filter.blank?
          update    = {"$set" => {"worker_name" => name, "state" => "running"}}
          query.sort(priority: 1, _id: 1).find_one_and_update(update, bypass_document_validation: true)
        end
      end
    else
      def find_and_assign_job
        SemanticLogger.silence(:info) do
          scheduled = {"$or" => [{run_at: nil}, {:run_at.lte => Time.now}]}
          working   = {"$or" => [{state: :queued}, {state: :running, sub_state: :processing}]}
          query     = RocketJob::Job.and(working, scheduled)
          query     = query.where(current_filter) unless current_filter.blank?
          update    = {"$set" => {"worker_name" => name, "state" => "running"}}
          query.sort(priority: 1, _id: 1).find_one_and_update(update, bypass_document_validation: true)
        end
      end
    end

    # Add the supplied filter to the current filter.
    def add_to_current_filter(filter)
      filter.each_pair do |k, v|
        current_filter[k] =
          if (previous = current_filter[k])
            v.is_a?(Array) ? previous + v : v
          else
            v
          end
      end
      current_filter
    end

    # Returns [Float] a randomized poll interval in seconds up to the maximum configured poll interval.
    def random_wait_interval
      rand(Config.max_poll_seconds * 1000) / 1000
    end
  end
end

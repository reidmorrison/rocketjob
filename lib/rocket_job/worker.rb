module RocketJob
  # Worker
  #
  # A worker runs on a single operating system thread
  # Is usually started under a Rocket Job server process.
  class Worker
    include SemanticLogger::Loggable

    attr_accessor :id, :current_filter
    attr_reader :name, :server_name

    # Raised when a worker is killed so that it shutdown immediately, yet cleanly.
    #
    # Note:
    # - It is not recommended to catch this exception since it is to shutdown workers quickly.
    class Shutdown < RuntimeError
    end

    # Returns [String] the name of the worker with the supplied id on the named server, such as "host:1234:3", which
    # jobs and slices hold as their `worker_name`. Read it with .on_server?, .on_server_pattern and .server_name_of.
    def self.worker_name(server_name, id)
      "#{server_name}:#{id}"
    end

    # Returns [true|false] whether the supplied worker name is the name of a worker on the named server, see
    # .worker_name: the server's name followed by the worker's id, or the name of the server itself, such as "inline".
    # Only a server whose name does not end with `:` and a number can be a worker name itself, since .server_name_of
    # reads that number as a worker id.
    # A server whose name starts with the same characters is another server: the workers of "host:123" are not on
    # "host:12", and those of "host:2" are not on "host".
    def self.on_server?(worker_name, server_name)
      return false if worker_name.blank? || server_name.blank?

      worker_name.match?(on_server_pattern(server_name))
    end

    # Returns [Regexp] that matches the worker names that .on_server? accepts for the named server, to select them in
    # a query, such as the slices that the workers of a server that died were processing.
    def self.on_server_pattern(server_name)
      /\A#{Regexp.escape(server_name)}(?::\d+)?\z/
    end

    # Returns [String] the name of the server of the supplied worker name, see .worker_name, such as "host:1234" for
    # "host:1234:3", or the supplied name when it does not end with a worker id, such as "inline". The name of a server
    # that ends with a number, such as the default "host:1234", see Config.server_name, is read as "host" with the
    # worker id 1234, so it is never a worker name without a worker id.
    def self.server_name_of(worker_name)
      worker_name.to_s.sub(/:\d+\z/, "")
    end

    def initialize(id: 0, server_name: "inline:0")
      @id             = id
      @server_name    = server_name
      @name           = self.class.worker_name(server_name, id)
      @re_check_start = Time.now
      @current_filter = Config.filter || {}
    end

    def alive?
      true
    end

    def backtrace
      Thread.current.backtrace
    end

    def join(*_args)
      true
    end

    def kill
      true
    end

    def shutdown?
      false
    end

    def shutdown!
      true
    end

    # Returns [true|false] whether the shutdown indicator was set
    def wait_for_shutdown?(_timeout = nil)
      false
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
        reset_filter_if_expired
        job = next_available_job

        if job
          # Returns true when this job has no more work immediately available,
          # for example a batch job that has run out of slices, or was throttled.
          no_immediate_work = job.rocket_job_work(self, false)

          # Return the database connections for this thread back to the connection pool.
          release_active_record_connections

          sleep_seconds =
            if no_immediate_work
              # Stagger workers so that they don't all poll at the same time.
              random_wait_interval
            else
              # Work was performed and more queued work is likely available,
              # so poll again immediately rather than waiting a full interval.
              0
            end
        else
          # No work was found, so wait the full poll interval before checking again.
          sleep_seconds = Config.max_poll_seconds
        end

        wait_for_shutdown?(sleep_seconds)
      end

      logger.info "Stopping"
    rescue Exception => e
      logger.fatal("Unhandled exception in job processing thread", e)
    ensure
      release_active_record_connections
    end

    # Return the database connections for this thread back to the connection pool.
    def release_active_record_connections
      RocketJob.release_active_record_connections
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
        # Job failed during throttle execution?
        next if job.failed?

        # Start this job!
        job.fail_on_exception! { job.start!(name) }
        return job if job.running?
      end
    end

    # Whether the supplied job has been throttled and should be ignored.
    def throttled_job?(job)
      # Evaluate job throttles, if any.
      throttle = job.rocket_job_throttles.matching_throttle(job)
      return false unless throttle

      add_to_current_filter(throttle.extract_filter(job))
      # Restore retrieved job so that other workers can process it later, recording
      # why it was throttled so it is visible in Mission Control. This reuses the
      # write that requeues the job, so it adds no extra database round trip.
      job.set(
        worker_name:  nil,
        state:        :queued,
        throttled_by: throttle.extract_description(job),
        throttled_at: Time.now
      )
      true
    end

    # Finds the next job to work on in priority based order
    # and assigns it to this worker.
    #
    # Applies the current filter to exclude filtered jobs.
    #
    # Returns nil if no jobs are available for processing.
    #
    # Notes:
    # - An already running batch job is _joined_ with a read-only query, since
    #   concurrency for a batch job is coordinated per-slice (see
    #   `Sliced::Input#next_slice`), not on the job document. Writing
    #   `worker_name`/`state` to the shared job document on every poll turns it
    #   into a write-contention hotspot: with many workers MongoDB serializes the
    #   updates and retries the write conflicts (server log id 46404), which is
    #   what makes a large batch job slow down as workers are added.
    # - Only a queued job is claimed with a write, transitioning it to running.
    #   That write is naturally distributed: each queued job is claimed once.
    def find_and_assign_job
      SemanticLogger.silence(:info) do
        scheduled = RocketJob::Job.where(run_at: nil).or(:run_at.lte => Time.now)
        working   = RocketJob::Job.queued.or(state: "running", sub_state: "processing")
        query     = RocketJob::Job.and(working, scheduled)
        query     = query.and(current_filter) unless current_filter.blank?
        query     = query.sort(priority: 1, _id: 1)

        # Retry only when a queued job was claimed by another worker first.
        loop do
          job = query.first
          return nil unless job

          # Already running batch job: join it without writing to the job document.
          return job if job.running?

          # Queued job: claim it atomically, guarding on it still being queued.
          # find_one_and_update returns the pre-image (state: queued) so that the
          # caller still runs throttles and `start!`.
          # Clear any stale throttle reason from a previous throttled poll so a job
          # that is now allowed to run no longer reports as throttled in Mission Control.
          update = {
            "$set"   => {"worker_name" => name, "state" => "running"},
            "$unset" => {"throttled_by" => "", "throttled_at" => ""}
          }
          claimed = RocketJob::Job.queued.where(id: job.id).
                    find_one_and_update(update, bypass_document_validation: true)
          return claimed if claimed
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

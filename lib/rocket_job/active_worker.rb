module RocketJob
  # Information about a server currently working on a job
  class ActiveWorker
    # When this server started working on this job / slice
    attr_accessor :started_at

    attr_accessor :job
    attr_reader :name

    # Returns [Hash<String:ActiveWorker>] hash of all servers sorted by name
    # and what they are currently working on.
    # Returns {} if no servers are currently busy doing any work
    #
    # Parameters
    #   server_name: [String]
    #     Only jobs running on the specified server
    def self.all(server_name = nil)
      servers = []
      # Need paused, failed or aborted since servers may still be working on active slices
      query = RocketJob::Job.where(:state.in => %i[running paused failed aborted])
      if server_name
        # The workers of a batch job that is processing its slices can be on any server, see
        # RocketJob::Batch::Worker#rocket_job_active_workers.
        query = query.any_of({worker_name: RocketJob::Worker.on_server_pattern(server_name)}, {sub_state: "processing"})
      end
      query.each do |job|
        servers += job.rocket_job_active_workers(server_name)
      end
      servers
    end

    # Requeues all jobs for which the workers have disappeared
    def self.requeue_zombies
      all.each do |active_worker|
        next if !active_worker.zombie? || !active_worker.job.may_requeue?(active_worker.server_name)

        active_worker.job.requeue!(active_worker.server_name)
      end
    end

    def initialize(name, started_at, job)
      @name       = name
      @started_at = started_at
      @job        = job
    end

    # Duration in human readable form
    def duration
      RocketJob.seconds_as_duration(duration_s)
    end

    # Number of seconds this server has been working on this job / slice
    def duration_s
      Time.now - (started_at || Time.now)
    end

    # Returns [String] the name of the server running this worker, see RocketJob::Worker.server_name_of.
    def server_name
      RocketJob::Worker.server_name_of(name)
    end

    def server
      @server ||= RocketJob::Server.where(name: server_name).first
    end

    # The server on which this worker was running is no longer running
    def zombie?
      server.nil?
    end

    def name=(name)
      @server = nil
      @name   = name
    end
  end
end

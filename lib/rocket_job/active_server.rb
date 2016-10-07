module RocketJob
  # Information about a server currently working on a job
  class ActiveServer
    # When this server started working on this job / slice
    attr_accessor :started_at

    attr_accessor :name, :job

    # Returns [Hash<String:ActiveWorker>] hash of all servers sorted by name
    # and what they are currently working on.
    # Returns {} if no servers are currently busy doing any work
    def self.all
      servers = {}
      # Need paused, failed or aborted since servers may still be working on active slices
      RocketJob::Job.where(state: [:running, :paused, :failed, :aborted]).each do |job|
        job.rocket_job_active_servers.each_pair do |name, active_server|
          (servers[name] ||= []) << active_server
        end
      end
      servers
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
      Time.now - started_at
    end

    def server
      @server ||= RocketJob::Server.find_by(name: name)
    end

    def name=(name)
      @server = nil
      @name   = name
    end
  end
end

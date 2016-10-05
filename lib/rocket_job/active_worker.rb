module RocketJob
  # Information about a worker currently working on a job
  class ActiveWorker
    # When this worker started working on this job / slice
    attr_accessor :started_at

    attr_accessor :worker_name, :job

    # Returns [Hash<String:ActiveWorker>] hash of all workers sorted by name
    # and what they are currently working on.
    # Returns {} if no workers are currently busy doing any work
    def self.all
      workers = {}
      # Need paused, failed or aborted since workers may still be working on active slices
      RocketJob::Job.where(state: [:running, :paused, :failed, :aborted]).each do |job|
        job.rocket_job_active_workers.each_pair do |worker_name, active_worker|
          (workers[worker_name] ||= []) << active_worker
        end
      end
      workers
    end

    def initialize(worker_name, started_at, job)
      @worker_name = worker_name
      @started_at  = started_at
      @job         = job
    end

    # Duration in human readable form
    def duration
      RocketJob.seconds_as_duration(duration_s)
    end

    # Number of seconds this worker has been working on this job / slice
    def duration_s
      Time.now - started_at
    end

    def worker
      @worker ||= RocketJob::Worker.find_by(worker_name: worker_name)
    end

    def worker_name=(worker_name)
      @worker      = nil
      @worker_name = worker_name
    end
  end
end

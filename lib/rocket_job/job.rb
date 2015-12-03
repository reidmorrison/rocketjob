# encoding: UTF-8
module RocketJob
  # The base job from which all jobs are created
  class Job
    include Concerns::Document
    include Concerns::Persistence
    include Concerns::EventCallbacks
    include Concerns::Callbacks
    include Concerns::Logger
    include Concerns::StateMachine
    include Concerns::JobStateMachine
    include Concerns::Worker
    include Concerns::Defaults

    # User definable properties in Dirmon Entry
    def self.rocket_job_properties
      @rocket_job_properties ||= (self == RocketJob::Job ? [] : superclass.rocket_job_properties)
    end

    # Add to user definable properties in Dirmon Entry
    def self.public_rocket_job_properties(*properties)
      rocket_job_properties.concat(properties).uniq!
    end

    # User definable properties in Dirmon Entry
    public_rocket_job_properties :description, :priority, :log_level, :arguments

    # Requeues all jobs that were running on worker that died
    def self.requeue_dead_worker(worker_name)
      running.each { |job| job.requeue!(worker_name) if job.may_requeue?(worker_name) }
    end

    # Pause all running jobs
    def self.pause_all
      running.each(&:pause!)
    end

    # Resume all paused jobs
    def self.resume_all
      paused.each(&:resume!)
    end

    # Returns the number of required arguments for this job
    def self.argument_count
      instance_method(:perform).arity
    end

    # Returns [true|false] whether to collect the results from running this batch
    def collect_output?
      collect_output == true
    end

    # Returns [Float] the number of seconds the job has taken
    # - Elapsed seconds to process the job from when a worker first started working on it
    #   until now if still running, or until it was completed
    # - Seconds in the queue if queued
    def seconds
      if completed_at
        completed_at - (started_at || created_at)
      elsif started_at
        Time.now - started_at
      else
        Time.now - created_at
      end
    end

    # Returns a human readable duration the job has taken
    def duration
      RocketJob.seconds_as_duration(seconds)
    end

    # A job has expired if the expiry time has passed before it is started
    def expired?
      started_at.nil? && expires_at && (expires_at < Time.now)
    end

    # Returns [Hash] status of this job
    def as_json
      attrs = serializable_hash(methods: [:seconds, :duration])
      attrs.delete('result') unless collect_output?
      case
      when running?
        attrs.delete('completed_at')
        attrs.delete('result')
        attrs
      when paused?
        attrs.delete('completed_at')
        attrs.delete('result')
        # Ensure 'paused_at' appears first in the hash
        {'paused_at' => completed_at}.merge(attrs)
      when aborted?
        attrs.delete('completed_at')
        attrs.delete('result')
        {'aborted_at' => completed_at}.merge(attrs)
      when failed?
        attrs.delete('completed_at')
        attrs.delete('result')
        {'failed_at' => completed_at}.merge(attrs)
      else
        attrs
      end
    end

    # Returns [Hash] the status of this job
    def status(time_zone = 'Eastern Time (US & Canada)')
      h = as_json
      h.delete('seconds')
      h.dup.each_pair do |k, v|
        case
        when v.is_a?(Time)
          h[k] = v.in_time_zone(time_zone).to_s
        when v.is_a?(BSON::ObjectId)
          h[k] = v.to_s
        end
      end
      h
    end

    # Sets the exception child object for this job based on the
    # supplied Exception instance or message
    def set_exception(worker_name='', exc_or_message='')
      if exc_or_message.is_a?(Exception)
        self.exception        = JobException.from_exception(exc_or_message)
        exception.worker_name = worker_name
      else
        build_exception(
          class_name:  'RocketJob::JobException',
          message:     exc_or_message,
          backtrace:   [],
          worker_name: worker_name
        )
      end
    end

  end
end

#require 'rocketjob'

module ActiveJob
  module QueueAdapters
    # == Rocket Job adapter for Active Job
    #
    # Ruby's missing batch system.
    #
    # Read more about Rocket Job {here}[http://rocketjob.io].
    #
    # To use Rocket Job set the queue_adapter config to +:rocket_job+.
    #
    #   Rails.application.config.active_job.queue_adapter = :rocket_job
    class RocketJobAdapter
      def enqueue(active_job) #:nodoc:
        rocket_job                 = JobWrapper.perform_later(active_job.serialize) do |job|
          job.active_job_id    = active_job.job_id
          job.active_job_class = active_job.class.name
          job.active_job_queue = active_job.queue_name
          job.description      = active_job.class.name
          job.priority         = active_job.priority if active_job.priority
        end
        active_job.provider_job_id = rocket_job.id.to_s
        rocket_job
      end

      def enqueue_at(active_job, timestamp) #:nodoc:
        rocket_job                 = JobWrapper.perform_later(active_job.serialize) do |job|
          job.active_job_id    = active_job.job_id
          job.active_job_class = active_job.class.name
          job.active_job_queue = active_job.queue_name
          job.description      = active_job.class.name
          job.priority         = active_job.priority if active_job.priority
          job.run_at           = Time.at(timestamp).utc
        end
        active_job.provider_job_id = rocket_job.id.to_s
        rocket_job
      end

      class JobWrapper < RocketJob::Job #:nodoc:
        key :active_job_id, String
        key :active_job_class, String
        key :active_job_queue, String

        def perform(job_data)
          Base.execute job_data
        end
      end
    end
  end
end

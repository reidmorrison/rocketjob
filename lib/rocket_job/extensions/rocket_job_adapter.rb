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
    # In application.rb add the following line:
    #   config.active_job.queue_adapter = :rocket_job
    #
    # Example:
    #
    # Create a new file in app/job/my_job.rb:
    #
    #   class MyJob < ActiveJob::Base
    #     def perform(record)
    #       p "Received: #{record}"
    #     end
    #   end
    #
    # Run the job inline to verify ActiveJob is working:
    #
    #   MyJob.perform_now('hello world')
    #
    # Enqueue the job for processing:
    #
    #   MyJob.perform_later('hello world')
    #
    # Enqueue the job for processing, 5 minutes from now:
    #
    #   MyJob.set(wait: 5.minutes).perform_later('hello world')
    #
    # Start RocketJob server (or, restart if already running)
    #
    #   bundle exec rocketjob
    #
    # Override the priority of the job:
    #
    #   class MyJob < ActiveJob::Base
    #     queue_with_priority 20
    #
    #     def perform(record)
    #       p "Received: #{record}"
    #     end
    #   end
    #
    # Notes:
    # - ActiveJobs will appear in:
    #   - Queued before the are processed.
    #   - Failed if the fail to process.
    #   - Scheduled if they are to be processed in the future.
    #   - Completed jobs will not appear in completed since the Active Job adapter
    #     uses the default Rocket Job `destroy_on_completion` of `false`.
    class RocketJobAdapter
      def self.enqueue(active_job) #:nodoc:
        job                        = RocketJob::Jobs::ActiveJob.create!(active_job_params(active_job))
        active_job.provider_job_id = job.id.to_s if active_job.respond_to?(:provider_job_id=)
        job
      end

      def self.enqueue_at(active_job, timestamp) #:nodoc:
        params          = active_job_params(active_job)
        params[:run_at] = Time.at(timestamp).utc

        job                        = RocketJob::Jobs::ActiveJob.create!(params)
        active_job.provider_job_id = job.id.to_s if active_job.respond_to?(:provider_job_id=)
        job
      end

      def self.active_job_params(active_job)
        params            = {
          description:      active_job.class.name,
          data:             active_job.serialize,
          active_job_id:    active_job.job_id,
          active_job_class: active_job.class.name,
          active_job_queue: active_job.queue_name
        }
        params[:priority] = active_job.priority if active_job.respond_to?(:priority) && active_job.priority
        params
      end
      private_class_method :active_job_params
    end
  end
end

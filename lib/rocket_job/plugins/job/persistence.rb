require "active_support/concern"

module RocketJob
  module Plugins
    module Job
      # Where jobs are stored, and saving a new instance of a job when it restarts.
      module Persistence
        extend ActiveSupport::Concern

        included do
          # Store all job types in this collection
          store_in collection: "rocket_job.jobs"
        end

        # Create a new instance of this job, copying across only the `copy_on_restart` attributes, and what the plugins
        # of this job keep, such as the input and output categories of a batch job, with their settings, such as
        # `slice_size`, see #rocket_job_restart_copy_to.
        def create_restart!(**overrides)
          if expired?
            logger.info("Job has expired. Not creating a new instance.")
            return
          end

          job_attrs = self.class.rocket_job_restart_attributes.to_h do |attr|
            [attr, send(attr)]
          end
          job_attrs.merge!(overrides)

          job = self.class.new(job_attrs)
          rocket_job_restart_copy_to(job)
          job.save_with_retry!

          logger.info("Created a new job instance: #{job.id}")
        end

        # Set in-memory job to complete if `destroy_on_complete` and the job has been destroyed
        def reload
          return super unless destroy_on_complete

          begin
            super
          rescue ::Mongoid::Errors::DocumentNotFound
            unless completed?
              self.state = :completed
              rocket_job_set_completed_at
              rocket_job_mark_complete
            end
            self
          end
        end

        # Save with retry in case persistence takes a moment.
        def save_with_retry!(retry_limit = 10, sleep_interval = 0.5)
          count = 0
          while count < retry_limit
            return true if save

            logger.info("Retrying to persist new scheduled instance: #{errors.messages.inspect}")
            sleep(sleep_interval)
            count += 1
          end
          save!
        end

        private

        # Copies to the supplied new instance of this job, see #create_restart!, what a plugin keeps when the job
        # restarts, besides the `copy_on_restart` fields. A plugin that keeps more overrides it, and calls super.
        def rocket_job_restart_copy_to(_job)
        end
      end
    end
  end
end

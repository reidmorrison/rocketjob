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

        # Create a new instance of this job, copying across only the `copy_on_restart` attributes.
        # Copy across input and output categories to new scheduled job so that all of the
        # settings are remembered between instance. Example: slice_size
        def create_restart!(**overrides)
          if expired?
            logger.info("Job has expired. Not creating a new instance.")
            return
          end

          job_attrs = self.class.rocket_job_restart_attributes.to_h do |attr|
            [attr, send(attr)]
          end
          job_attrs.merge!(overrides)

          job                   = self.class.new(job_attrs)
          job.input_categories  = input_categories if respond_to?(:input_categories)
          job.output_categories = output_categories if respond_to?(:output_categories)

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
      end
    end
  end
end

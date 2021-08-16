require "active_support/concern"

module RocketJob
  module Plugins
    module Job
      # Prevent more than one instance of this job class from running at a time
      module Persistence
        extend ActiveSupport::Concern

        included do
          # Store all job types in this collection
          store_in collection: "rocket_job.jobs"
        end

        module ClassMethods
          # Returns [Hash<String:Integer>] of the number of jobs in each state
          # Queued jobs are separated into :queued_now and :scheduled
          #   :queued_now are jobs that are awaiting processing and can be processed now.
          #   :scheduled are jobs scheduled to run the future.
          #
          # Note: If there are no jobs in that particular state then the hash will not have a value for it
          #
          # Example jobs in every state:
          #   RocketJob::Job.counts_by_state
          #   # => {
          #          :aborted => 1,
          #          :completed => 37,
          #          :failed => 1,
          #          :paused => 3,
          #          :queued => 4,
          #          :running => 1,
          #          :queued_now => 1,
          #          :scheduled => 3
          #        }
          #
          # Example jobs some states:
          #   RocketJob::Job.counts_by_state
          #   # => {
          #          :failed => 1,
          #          :running => 25,
          #          :completed => 1237
          #        }
          def counts_by_state
            counts = {}
            collection.aggregate(
              [
                {
                  "$group" => {
                    _id:   "$state",
                    count: {"$sum" => 1}
                  }
                }
              ]
            ).each do |result|
              counts[result["_id"].to_sym] = result["count"]
            end

            # Calculate :queued_now and :scheduled if there are queued jobs
            if (queued_count = counts[:queued])
              scheduled_count = RocketJob::Job.scheduled.count
              if scheduled_count.positive?
                queued_now_count    = queued_count - scheduled_count
                counts[:queued_now] = queued_count - scheduled_count if queued_now_count.positive?
                counts[:scheduled]  = scheduled_count
              else
                counts[:queued_now] = queued_count
              end
            end
            counts
          end
        end

        # Create a new instance of this job, copying across only the `copy_on_restart` attributes.
        # Copy across input and output categories to new scheduled job so that all of the
        # settings are remembered between instance. Example: slice_size
        def create_restart!(**overrides)
          if expired?
            logger.info("Job has expired. Not creating a new instance.")
            return
          end

          job_attrs = self.class.rocket_job_restart_attributes.each_with_object({}) do |attr, attrs|
            attrs[attr] = send(attr)
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

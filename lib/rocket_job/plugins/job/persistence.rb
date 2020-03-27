require 'active_support/concern'

module RocketJob
  module Plugins
    module Job
      # Prevent more than one instance of this job class from running at a time
      module Persistence
        extend ActiveSupport::Concern

        included do
          # Store all job types in this collection
          store_in collection: 'rocket_job.jobs'
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
                  '$group' => {
                    _id:   '$state',
                    count: {'$sum' => 1}
                  }
                }
              ]
            ).each do |result|
              counts[result['_id'].to_sym] = result['count']
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
      end
    end
  end
end

# encoding: UTF-8
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

          after_initialize :remove_arguments
        end

        module ClassMethods
          # Retrieves the next job to work on in priority based order
          # and assigns it to this worker
          #
          # Returns nil if no jobs are available for processing
          #
          # Parameters
          #   worker_name: [String]
          #     Name of the worker that will be processing this job
          #
          #   filter: [Hash]
          #     Filter to apply to the query.
          #     For example: to exclude jobs from being returned.
          #
          # Example:
          #   # Skip any job ids from the job_ids_list
          #   filter = {:id.nin => job_ids_list}
          #   job    = RocketJob::Job.rocket_job_retrieve('host:pid:worker', filter)
          def rocket_job_retrieve(worker_name, filter)
            SemanticLogger.silence(:info) do
              query  = queued_now
              query  = query.where(filter) unless filter.blank?
              update = {'$set' => {'worker_name' => worker_name, 'state' => 'running', 'started_at' => Time.now}}
              query.sort(priority: 1, _id: 1).find_one_and_update(update, bypass_document_validation: true)
            end
          end

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
            collection.aggregate([
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
            if queued_count = counts[:queued]
              scheduled_count = RocketJob::Job.scheduled.count
              if scheduled_count > 0
                queued_now_count    = queued_count - scheduled_count
                counts[:queued_now] = queued_count - scheduled_count if queued_now_count > 0
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
          rescue Mongoid::Errors::DocumentNotFound
            unless completed?
              self.state = :completed
              rocket_job_set_completed_at
              rocket_job_mark_complete
            end
            self
          end
        end

        private

        # Remove old style arguments that were stored as an array
        def remove_arguments
          attributes.delete('arguments') unless respond_to?('arguments='.to_sym)
        end

      end
    end
  end
end

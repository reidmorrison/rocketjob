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
          set_collection_name 'rocket_job.jobs'

          # Create indexes
          def self.create_indexes
            # Used by find_and_modify in .rocket_job_retrieve
            ensure_index({state: 1, priority: 1, _id: 1}, background: true)
            # Remove outdated indexes if present
            drop_index('state_1_run_at_1_priority_1_created_at_1_sub_state_1') rescue nil
            drop_index('state_1_priority_1_created_at_1_sub_state_1') rescue nil
            drop_index('state_1_priority_1_created_at_1') rescue nil
            drop_index('created_at_1') rescue nil
          end

          # Retrieves the next job to work on in priority based order
          # and assigns it to this worker
          #
          # Returns nil if no jobs are available for processing
          #
          # Parameters
          #   worker_name [String]
          #     Name of the worker that will be processing this job
          #
          #   skip_job_ids [Array<BSON::ObjectId>]
          #     Job ids to exclude when looking for the next job
          def self.rocket_job_retrieve(worker_name, skip_job_ids = nil)
            run_at       = [
              {run_at: {'$exists' => false}},
              {run_at: {'$lte' => Time.now}}
            ]
            query        =
              if defined?(RocketJobPro)
                {
                  '$and' => [
                    {
                      '$or' => [
                        {'state' => 'queued'}, # Jobs
                        {'state' => 'running', 'sub_state' => :processing} # Slices
                      ]
                    },
                    {
                      '$or' => run_at
                    }
                  ]
                }
              else
                {
                  'state' => 'queued',
                  '$or'   => run_at
                }
              end

            query['_id'] = {'$nin' => skip_job_ids} if skip_job_ids && skip_job_ids.size > 0

            if doc = find_and_modify(
              query:  query,
              sort:   {priority: 1, _id: 1},
              update: {'$set' => {'worker_name' => worker_name, 'state' => 'running'}}
            )
              load(doc)
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
          def self.counts_by_state
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
              counts[result['_id']] = result['count']
            end

            # Calculate :queued_now and :scheduled if there are queued jobs
            if queued_count = counts[:queued]
              scheduled_count = RocketJob::Job.where(state: :queued, run_at: {'$gt' => Time.now}).count
              if scheduled_count > 0
                queued_now_count = queued_count - scheduled_count
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
          rescue MongoMapper::DocumentNotFound
            unless completed?
              self.state = :completed
              rocket_job_set_completed_at
              rocket_job_mark_complete
            end
            self
          end
        end

        private

        # After this model is loaded, convert any hashes in the arguments list to HashWithIndifferentAccess
        def load_from_database(*args)
          super
          if arguments.present?
            self.arguments = arguments.collect { |i| i.is_a?(BSON::OrderedHash) ? i.with_indifferent_access : i }
          end
        end

        # Apply RocketJob defaults after initializing default values
        # but before setting attributes. after_initialize is too late
        def initialize_default_values(except = {})
          super
          rocket_job_set_defaults
        end

      end
    end
  end
end

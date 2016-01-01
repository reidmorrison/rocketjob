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
            ensure_index({state: 1, priority: 1, created_at: 1}, background: true)
            # Remove outdated indexes if present
            drop_index('state_1_run_at_1_priority_1_created_at_1_sub_state_1') rescue nil
            drop_index('state_1_priority_1_created_at_1_sub_state_1') rescue nil
            # Used by Mission Control
            ensure_index [[:created_at, 1]]
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
            query        = {
              '$and' => [
                {
                  '$or' => [
                    {'state' => 'queued'}, # Jobs
                    {'state' => 'running', 'sub_state' => :processing} # Slices
                  ]
                },
                {
                  '$or' => [
                    {run_at: {'$exists' => false}},
                    {run_at: {'$lte' => Time.now}}
                  ]
                }
              ]
            }
            query['_id'] = {'$nin' => skip_job_ids} if skip_job_ids && skip_job_ids.size > 0

            if doc = find_and_modify(
              query:  query,
              sort:   {priority: 1, created_at: 1},
              update: {'$set' => {'worker_name' => worker_name, 'state' => 'running'}}
            )
              load(doc)
            end
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

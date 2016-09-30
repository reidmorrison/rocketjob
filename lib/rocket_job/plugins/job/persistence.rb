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

          after_initialize :rocket_job_make_indifferent_arguments

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
            query  = queued_now
            update = {'$set' => {'worker_name' => worker_name, 'state' => 'running', 'started_at' => Time.now}}

            query  = query.where(:id.nin => skip_job_ids) if skip_job_ids && skip_job_ids.size > 0

            query.sort(priority: 1, _id: 1).find_one_and_update(update)
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
              counts[result['_id'].to_sym] = result['count']
            end

            # Calculate :queued_now and :scheduled if there are queued jobs
            if queued_count = counts[:queued]
              scheduled_count = RocketJob::Job.queued.where(:run_at.gt => Time.now).count
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
          rescue Mongoid::DocumentNotFound
            unless completed?
              self.state = :completed
              rocket_job_set_completed_at
              rocket_job_mark_complete
            end
            self
          end
        end

        private

        # after_find: convert any hashes in the arguments list to HashWithIndifferentAccess
        def rocket_job_make_indifferent_arguments
          return unless arguments.present?
          self.arguments = arguments.collect { |i| i.is_a?(Hash) ? i.with_indifferent_access : i }
        end

      end
    end
  end
end

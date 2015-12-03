# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Concerns
    # Prevent more than one instance of this job class from running at a time
    module Persistence
      extend ActiveSupport::Concern

      included do
        # Prevent data in MongoDB from re-defining the model behavior
        #self.static_keys = true

        #
        # User definable attributes
        #
        # The following attributes are set when the job is created
        # @formatter:off

        # Description for this job instance
        key :description,             String

        # Priority of this job as it relates to other jobs [1..100]
        #   1: Highest Priority
        #  50: Default Priority
        # 100: Lowest Priority
        #
        # Example:
        #   A job with a priority of 40 will execute before a job with priority 50
        #
        # In RocketJob Pro, if a SlicedJob is running and a higher priority job
        # arrives, then the current job will complete the current slices and process
        # the new higher priority job
        key :priority,                Integer, default: 50

        # Run this job no earlier than this time
        key :run_at,                  Time

        # If a job has not started by this time, destroy it
        key :expires_at,              Time

        # When specified a job will be re-scheduled to run at it's next scheduled interval
        # Format is the same as cron.
        # #TODO Future capability.
        #key :schedule,                String

        # When the job completes destroy it from both the database and the UI
        key :destroy_on_complete,     Boolean, default: true

        # Any user supplied arguments for the method invocation
        # All keys must be UTF-8 strings. The values can be any valid BSON type:
        #   Integer
        #   Float
        #   Time    (UTC)
        #   String  (UTF-8)
        #   Array
        #   Hash
        #   True
        #   False
        #   Symbol
        #   nil
        #   Regular Expression
        #
        # Note: Date is not supported, convert it to a UTC time
        key :arguments,               Array

        # Whether to store the results from this job
        key :collect_output,          Boolean, default: false

        # Raise or lower the log level when calling the job
        # Can be used to reduce log noise, especially during high volume calls
        # For debugging a single job can be logged at a low level such as :trace
        #   Levels supported: :trace, :debug, :info, :warn, :error, :fatal
        key :log_level,               Symbol

        #
        # Read-only attributes
        #

        # Current state, as set by the state machine. Do not modify this value directly.
        key :state,                   Symbol, default: :queued

        # When the job was created
        key :created_at,              Time, default: -> { Time.now }

        # When processing started on this job
        key :started_at,              Time

        # When the job completed processing
        key :completed_at,            Time

        # Number of times that this job has failed to process
        key :failure_count,           Integer, default: 0

        # This name of the worker that this job is being processed by, or was processed by
        key :worker_name,             String

        #
        # Values that jobs can update during processing
        #

        # Allow a job to updates its estimated progress
        # Any integer from 0 to 100
        key :percent_complete,        Integer, default: 0

        # Store the last exception for this job
        one :exception,               class_name: 'RocketJob::JobException'

        # Store the Hash result from this job if collect_output is true,
        # and the job returned actually returned a Hash, otherwise nil
        # Not applicable to SlicedJob jobs, since its output is stored in a
        # separate collection
        key :result,                  Hash

        # @formatter:on

        # Store all job types in this collection
        set_collection_name 'rocket_job.jobs'

        validates_presence_of :state, :failure_count, :created_at
        validates :priority, inclusion: 1..100
        validates :log_level, inclusion: SemanticLogger::LEVELS + [nil]

        # Create indexes
        def self.create_indexes
          # Used by find_and_modify in .next_job
          ensure_index({state: 1, run_at: 1, priority: 1, created_at: 1, sub_state: 1}, background: true)
          # Remove outdated index if present
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
            sort:   [['priority', 'asc'], ['created_at', 'asc']],
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
            set_completed_at
            mark_complete
          end
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

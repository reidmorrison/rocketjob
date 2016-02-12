# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Plugins
    module Job
      # Prevent more than one instance of this job class from running at a time
      module Model
        extend ActiveSupport::Concern

        included do
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

          # Returns [String] the singular name for this job class
          #
          # Example:
          #   job = DataStudyJob.new
          #   job.underscore_name
          #   # => "data_study"
          def self.underscore_name
            @underscore_name ||= name.sub(/Job$/, '').underscore
          end

          # Allow the collective name for this job class to be overridden
          def self.underscore_name=(underscore_name)
            @underscore_name = underscore_name
          end

          # Returns [String] the human readable name for this job class
          #
          # Example:
          #   job = DataStudyJob.new
          #   job.human_name
          #   # => "Data Study"
          def self.human_name
            @human_name ||= name.sub(/Job$/, '').titleize
          end

          # Allow the human readable job name for this job class to be overridden
          def self.human_name=(human_name)
            @human_name = human_name
          end

          # Returns [String] the collective name for this job class
          #
          # Example:
          #   job = DataStudyJob.new
          #   job.collective_name
          #   # => "data_studies"
          def self.collective_name
            @collective_name ||= name.sub(/Job$/, '').pluralize.underscore
          end

          # Allow the collective name for this job class to be overridden
          def self.collective_name=(collective_name)
            @collective_name = collective_name
          end

          # Scope for jobs scheduled to run in the future
          def self.scheduled
            queued.where(run_at: {'$gt' => Time.now})
          end

          # Scope for queued jobs that can run now
          # I.e. Queued jobs excluding scheduled jobs
          def self.queued_now
            queued.where(
              '$or' => [
                {run_at: {'$exists' => false}},
                {run_at: {'$lte' => Time.now}}
              ]
            )
          end

          # Returns the number of required arguments for this job
          def self.rocket_job_argument_count
            instance_method(:perform).arity
          end

          # User definable properties in Dirmon Entry
          def self.rocket_job_properties
            @rocket_job_properties ||= (self == RocketJob::Job ? [] : superclass.rocket_job_properties)
          end

          # Add to user definable properties in Dirmon Entry
          def self.public_rocket_job_properties(*properties)
            properties.each { |property| raise("Invalid public_rocket_job_property: #{property.inspect}") unless key?(property)}
            rocket_job_properties.concat(properties).uniq!
          end

          # User definable properties in Dirmon Entry
          public_rocket_job_properties :description, :priority, :log_level, :arguments
        end

        # Returns [true|false] whether to collect nil results from running this batch
        def collect_nil_output?
          collect_output? ? (collect_nil_output == true) : false
        end

        # Returns [true|false] whether to collect the results from running this batch
        def collect_output?
          collect_output == true
        end

        # Returns [Float] the number of seconds the job has taken
        # - Elapsed seconds to process the job from when a worker first started working on it
        #   until now if still running, or until it was completed
        # - Seconds in the queue if queued
        def seconds
          if completed_at
            completed_at - (started_at || created_at)
          elsif started_at
            Time.now - started_at
          else
            Time.now - created_at
          end
        end

        # Returns a human readable duration the job has taken
        def duration
          RocketJob.seconds_as_duration(seconds)
        end

        # Returns [true|false] whether the job has expired
        def expired?
          expires_at && (expires_at < Time.now)
        end

        # Returns [true|false] whether the job is scheduled to run in the future
        def scheduled?
          queued? && run_at.present? && (run_at > Time.now)
        end

        # Returns [Hash] status of this job
        def as_json
          attrs = serializable_hash(methods: [:seconds, :duration])
          attrs.delete('result') unless collect_output?
          attrs.delete('failure_count') unless failure_count > 0
          case
          when queued?
            attrs.delete('started_at')
            attrs.delete('completed_at')
            attrs.delete('result')
            attrs
          when running?
            attrs.delete('completed_at')
            attrs.delete('result')
            attrs
          when completed?
            attrs.delete('percent_complete')
            attrs
          when paused?
            attrs.delete('completed_at')
            attrs.delete('result')
            # Ensure 'paused_at' appears first in the hash
            {'paused_at' => completed_at}.merge(attrs)
          when aborted?
            attrs.delete('completed_at')
            attrs.delete('result')
            {'aborted_at' => completed_at}.merge(attrs)
          when failed?
            attrs.delete('completed_at')
            attrs.delete('result')
            {'failed_at' => completed_at}.merge(attrs)
          else
            attrs
          end
        end

        # Returns [Hash] the status of this job
        def status(time_zone = 'Eastern Time (US & Canada)')
          h = as_json
          h.delete('seconds')
          h.dup.each_pair do |k, v|
            case
            when v.is_a?(Time)
              h[k] = v.in_time_zone(time_zone).to_s
            when v.is_a?(BSON::ObjectId)
              h[k] = v.to_s
            end
          end
          h
        end

      end
    end
  end
end

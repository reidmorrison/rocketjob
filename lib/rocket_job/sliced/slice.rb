require 'forwardable'
module RocketJob
  module Sliced
    # A slice is an Array of Records, along with meta-data that is used
    # or set during processing of the individual records
    #
    # Note: Do _not_ create instances of this model directly, go via Slice#new
    #       so that the correct collection name is used.
    #
    # Example:
    #   slice = RocketJob::Sliced::Slice.new
    #   slice << 'first'
    #   slice << 'second'
    #   second = slice.at(1)
    #
    #   # The [] operator is for retrieving attributes:
    #   slice['state']
    #
    class Slice
      include RocketJob::Plugins::Document
      include RocketJob::Plugins::StateMachine
      extend Forwardable

      store_in client: 'rocketjob_slices'

      # The record number of the first record in this slice.
      #
      # Optional: If present the record_number is set while the job
      #           is being processed.
      field :first_record_number, type: Integer

      #
      # Read-only attributes
      #

      # Current state, as set by AASM
      field :state, type: Symbol, default: :queued

      # When processing started on this slice
      field :started_at, type: Time

      # Number of times that this job has failed to process
      field :failure_count, type: Integer

      # This name of the worker that this job is being processed by, or was processed by
      field :worker_name, type: String

      # The last exception for this slice if any
      embeds_one :exception, class_name: 'RocketJob::JobException'

      after_find :parse_records

      # State Machine events and transitions
      #
      # Each slice is processed separately:
      #   :queued -> :running -> :completed
      #                       -> :failed     -> :running  ( manual )
      #
      # Slices are processed by ascending _id sort order
      #
      # Note:
      #   Currently all slices are destroyed on completion, so no slices
      #   are available in the completed state
      aasm column: :state, whiny_persistence: true do
        # Job has been created and is queued for processing ( Initial state )
        state :queued, initial: true

        # Job is running
        state :running

        # Job has completed processing ( End state )
        state :completed

        # Job failed to process and needs to be manually re-tried or aborted
        state :failed

        event :start, before: :set_started_at do
          transitions from: :queued, to: :running
        end

        event :complete do
          transitions from: :running, to: :completed
        end

        event :fail, before: :set_exception do
          transitions from: :running, to: :failed
          transitions from: :queued, to: :failed
        end

        event :retry do
          transitions from: :failed, to: :queued
        end
      end

      # `records` array has special handling so that it can be modified in place instead of having
      # to replace the entire array every time. For example, when appending lines with `<<`.
      def records
        @records ||= []
      end

      # Replace the records within this slice
      def records=(records)
        raise(ArgumentError, "Cannot assign type: #{records.class.name} to records") unless records.is_a?(Array)

        @records = records
      end

      def_instance_delegators :records, :each, :<<, :size, :concat, :at
      def_instance_delegators :records, *(Enumerable.instance_methods - Module.methods)

      # Fail this slice, along with the exception that caused the failure
      def set_exception(exc = nil, record_number = nil)
        if exc
          self.exception          = JobException.from_exception(exc)
          exception.worker_name   = worker_name
          exception.record_number = record_number
        end
        self.failure_count = failure_count.to_i + 1
        self.worker_name   = nil
      end

      # Returns [Hash] the slice as a Hash for storage purposes
      # Compresses / Encrypts the slice according to the job setting
      if ::Mongoid::VERSION.to_i >= 6
        def as_attributes
          attrs            = super
          attrs['records'] = serialize_records if @records
          attrs
        end
      else
        def as_document
          attrs            = super
          attrs['records'] = serialize_records if @records
          attrs
        end
      end

      def inspect
        "#{super[0...-1]}, records: #{@records.inspect}, collection_name: #{collection_name.inspect}>"
      end

      private

      # Always add records to any updates.
      def atomic_updates(*args)
        r = super(*args)
        if @records
          (r['$set'] ||= {})['records'] = serialize_records
        end
        r
      end

      def parse_records
        @records = attributes.delete('records')
      end

      def serialize_records
        records.mongoize
      end

      def set_started_at
        self.started_at = Time.now
      end
    end
  end
end

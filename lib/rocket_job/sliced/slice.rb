require "forwardable"
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

      store_in client: "rocketjob_slices"

      # What a worker of Rocket Job 7, which reads the records of a slice from "r", reads in place of the rows of a
      # file, see #records_document: the major version that reads them, which is not a list of records, so that it
      # raises NoMethodError, which fails the slice, rather than processing no records and removing the slice. The
      # slice can be retried once every server runs this version.
      ROWS_GUARD = 8

      # The record number of the first record in this slice.
      # Useful in knowing the line number of each record in this slice
      # relative to the original file that was uploaded. (1-based index)
      field :first_record_number, type: Integer, default: 1

      #
      # Read-only attributes
      #

      # Current state, as set by AASM
      field :state, type: Mongoid::StringifiedSymbol, default: :queued

      # When processing started on this slice
      field :started_at, type: Time

      # Number of times that this job has failed to process
      field :failure_count, type: Integer

      # Number of the record within this slice (not the entire file/job) currently being processed. (1-based index)
      field :processing_record_number, type: Integer

      # This name of the worker that this job is being processed by, or was processed by
      field :worker_name, type: String

      # The id of the upload that inserted this slice, when its uploader named one, so that the slices of that upload
      # can be removed again, see RocketJob::Sliced::Input#delete_upload.
      field :upload_id, type: String

      # The last exception for this slice if any
      embeds_one :exception, class_name: "RocketJob::JobException"

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

      # Returns whether this is a specialized binary slice for creating binary data from each slice
      # that is downloaded without conversion into output files.
      #
      # Since its text is not converted when it is downloaded, a binary slice writes it in the encoding of the output
      # file, which it holds as its `text_encoding`, see RocketJob::Sliced::Output#new.
      def self.binary_format
      end

      # For binary formats only, format the supplied records into the binary format for this slice
      def self.to_binary(_records)
        raise NotImplementedError
      end

      # `records` array has special handling so that it can be modified in place instead of having
      # to replace the entire array every time. For example, when appending lines with `<<`.
      #
      # Raises the error that reading the saved records raised, see #parse_records, such as for the rows of a file in a
      # format that this process does not have, so that the slice fails when it is processed, rather than the worker
      # that read it.
      def records
        raise(@records_error) if @records_error

        @records ||= []
      end

      # Replace the records within this slice.
      #
      # When the slice holds the rows of a file, see IOStreams::Slice, they keep the header row and format that they
      # carry, so that they are still read by them, such as when a copy of them, which is an Array, is changed and
      # assigned back. Records that are not rows, such as Hashes, are assigned as they are.
      def records=(records)
        raise(ArgumentError, "Cannot assign type: #{records.class.name} to records") unless records.is_a?(Array)

        @records_error = nil
        @records       = rows_of_file?(records) ? rows_like(@records, records) : records
      end

      # Returns [Array] the records of this slice from the supplied record number on, see #processing_record_number,
      # such as those that an earlier attempt did not process. The rows of a file keep the header row and format that
      # they carry.
      def records_from(record_number)
        return records if record_number <= 1

        rest = records[(record_number - 1)..] || []
        rows? ? rows_like(records, rest) : rest
      end

      def_instance_delegators :records, :each, :<<, :size, :concat, :at

      # Appends the supplied records after the records already in this slice, see Slices#append.
      def append_records(records)
        self.records = self.records + records
      end
      def_instance_delegators :records, *(Enumerable.instance_methods - Module.methods)

      # Returns [Integer] the record number of the record currently being processed relative to the entire file.
      def current_record_number
        first_record_number + (processing_record_number || 1) - 1
      end

      # Before Fail save the exception to this slice.
      def set_exception(exc = nil)
        self.exception     = JobException.from_failure(exc, worker_name: worker_name) if exc
        self.failure_count = failure_count.to_i + 1
        self.worker_name   = nil
      end

      # Returns the failed record.
      # Returns [nil] if there is no failed record
      def failed_record
        at(processing_record_number - 1) if exception && processing_record_number
      end

      # Replaces the record at the supplied index, such as a failed record once it is corrected, see #failed_record. The
      # records keep what they hold besides, such as the header row of the rows of a file, see IOStreams::Slice. Saved
      # with the slice.
      #
      # Raises IndexError when the slice has no record at the index.
      def replace_record(index, record)
        records.fetch(index)
        change_records { |changed| changed[index] = record }
      end

      # Removes the record at the supplied index, rather than every record equal to it. The records keep what they hold
      # besides, see #replace_record. Saved with the slice.
      #
      # Returns the record removed.
      # Raises IndexError when the slice has no record at the index.
      def delete_record(index)
        records.fetch(index)
        change_records { |changed| changed.delete_at(index) }
      end

      # Returns [Hash] the slice as a Hash for storage purposes
      # Compresses / Encrypts the slice according to the job setting
      def as_attributes
        attrs            = super
        attrs["records"] = serialize_records if @records
        attrs
      end

      def inspect
        "#{super[0...-1]}, records: #{@records.inspect}, collection_name: #{collection_name.inspect}>"
      end

      # Fail this slice if an exception occurs during processing.
      def fail_on_exception!(re_raise_exceptions = false, &)
        SemanticLogger.named_tagged(slice: id.to_s, &)
      rescue Exception => e
        SemanticLogger.named_tagged(slice: id.to_s) do
          if failed? || !may_fail?
            self.exception = JobException.from_exception(e, worker_name: worker_name)
            save! unless new_record? || destroyed?
          elsif new_record? || destroyed?
            fail(e)
          else
            fail!(e)
          end
          raise e if re_raise_exceptions
        end
      end

      private

      # Always add records to any updates.
      def atomic_updates(*args)
        r = super
        (r["$set"] ||= {})["records"] = serialize_records if @records
        r
      end

      def parse_records
        stored = attributes.delete("records")
        read_records do
          stored.is_a?(BSON::Binary) ? records_from_document(Hash.from_bson(BSON::ByteBuffer.new(stored.data))) : stored
        end
      end

      # Sets the records to those that the block reads from the saved document. An error that reading them raises is
      # held, and raised when the records are used, see #records, rather than by the query that read this slice, since a
      # worker reads it after claiming it, outside of the processing that fails the slice.
      def read_records
        @records_error = nil
        @records       = yield
      rescue StandardError => e
        @records_error = e
        @records       = nil
      end

      # The rows of a file are saved as the binary BSON of their document, see #records_document, so that a worker of
      # Rocket Job 7 does not read the Hash that holds them as records. Other records are saved as they are.
      def serialize_records
        rows? ? BSON::Binary.new(records_document.to_bson.to_s) : records.mongoize
      end

      # Returns [true|false] whether the records are the rows of a file, see IOStreams::Slice, which carry the header
      # row of their file and its format, so that they are read by them, see RocketJob::Category::Input#parse_records.
      def rows?
        records.is_a?(IOStreams::Slice)
      end

      # Returns [true|false] whether the supplied records replace the rows of a file that this slice holds with other
      # rows, see #records=, rather than with a slice of rows of their own, or with records that are not rows: Hashes.
      def rows_of_file?(records)
        @records.is_a?(IOStreams::Slice) && !records.is_a?(IOStreams::Slice) && records.none?(Hash)
      end

      # Yields the records to change, and returns what the block returns. Records that are frozen, such as the rows of a
      # file that IOStreams hands on, see IOStreams::Slice, are changed in a copy, which keeps the header row and format
      # that they carry, and which then replaces them.
      def change_records
        return yield(records) unless records.frozen?

        changed  = records.dup
        result   = yield(changed)
        @records = changed
        result
      end

      # Returns [IOStreams::Slice] the supplied rows, with what the supplied rows of a file carry: their header row, their
      # format, and whether their blank rows are records, such as the rows of a query, see IOStreams::Slice#blank_rows?.
      def rows_like(slice, rows)
        slice.dup.replace(rows)
      end

      # Returns [Hash] the document that holds the records: the rows of a file as the Hash that they return, see
      # IOStreams::Slice#to_h, which this slice does not read, under "s", with ROWS_GUARD under "r"; otherwise the
      # records under "r".
      def records_document
        rows? ? {"r" => ROWS_GUARD, "s" => records.to_h} : {"r" => records.to_a}
      end

      # Returns [Array] the records that the supplied document holds, see #records_document.
      def records_from_document(document)
        document.key?("s") ? IOStreams.slice(document["s"]) : document["r"]
      end

      # Before Start
      def set_started_at
        self.started_at = Time.now
      end
    end
  end
end

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

      # The record number of the record being processed, or once it is processed, the next one, see
      # #current_record_number. nil until a worker starts on this slice.
      #
      # A record number rather than a place in this slice, so that a record removed before a retry, see #delete_record,
      # does not move it to another record. A slice saved by Rocket Job 7 holds the place instead, which is converted
      # when it is read, see #convert_saved_position.
      field :processing_at_record, type: Integer

      # This name of the worker that this job is being processed by, or was processed by
      field :worker_name, type: String

      # The id of the upload that inserted this slice, when its uploader named one, so that the slices of that upload
      # can be removed again, see RocketJob::Sliced::Input#delete_upload.
      field :upload_id, type: String

      # The last exception for this slice if any
      embeds_one :exception, class_name: "RocketJob::JobException"

      after_find :parse_records
      after_find :convert_saved_position

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
      # The rows of a file, see IOStreams::Slice, are assigned as they are, with the line and record number of each row,
      # which each must have, see #records_from. When the slice holds the rows of a file, rows in an
      # Array keep the header row and format that they carry, so that they are still read by them, such as when a copy
      # of them, see #to_a, is changed and assigned back. They do not keep the numbers of each row, which
      # #replace_record and #delete_record do, but are numbered from #first_record_number, without lines, and keep those
      # numbers afterwards. Records that are not rows, such as Hashes, are assigned as they are.
      #
      # Since records assigned in an Array do not keep the numbers of the records that they replace, the slice then
      # points at the record in the same place as the record that it was processing, see #processing_at_record.
      def records=(records)
        unless records.is_a?(Array) || records.is_a?(IOStreams::Slice)
          raise(ArgumentError, "Cannot assign type: #{records.class.name} to records")
        end

        check_record_numbers(records) if records.is_a?(IOStreams::Slice)
        index          = current_index if processing_at_record && records.is_a?(Array) && @records && !@records_error
        @records_error = nil
        @records       = rows_of_file?(records) ? rows_like(@records, records) : records
        point_at_index(index) if index
      end

      # Returns [Array|IOStreams::Slice] the records of this slice from the record of the supplied record number on, see
      # #record_number_at, such as those that an earlier attempt did not process, see #processing_at_record: from the
      # first record that it still holds at or after it, so from its first record for a number before it, and none
      # after its last.
      #
      # The rows of a file are found by their record numbers, see IOStreams::Slice#from_record, and keep the header row
      # and format that they carry, and the line and record number of each row. Other records are numbered by their
      # place, see #record_number_at.
      def records_from(record_number)
        rows? ? records.from_record(record_number) : records.drop(record_index(record_number))
      end

      # Yields each record that is still to be processed, from the record being processed on, see
      # #processing_at_record, as the supplied input category reads it, through the supplied contract when there is one,
      # see Category::Input#parse_records, with the line of its file that it starts on, or nil when it is not a line of
      # a file, and its record number, see #record_number_at.
      #
      # Points #processing_at_record at each record before it is yielded, and once the block returns, at the next
      # record, since a record that cannot be parsed raises before the category yields it, so that a failure names
      # that record. After the last record it points after it, so that a slice that fails once every record is
      # processed, such as in an after_slice callback, has no failed record, see #failed_record, and its retry
      # processes none of them again, which would add their results to its output a second time.
      #
      # Yields nothing when this slice no longer holds the record that it was processing, nor a record after it, such as
      # once they were removed, see #delete_record.
      #
      # With a contract, see RocketJob::Batch::Contracts, a blank row is skipped, so the slice points at the record that
      # failed by the number that IOStreams' error names, see IOStreams::Errors::RowError#record_number, and after its
      # last row once every record is processed.
      def each_unprocessed_record(category, contract: nil)
        index = current_index
        return if index >= size

        number                    = record_number_at(index)
        self.processing_at_record = number
        records                   = records_after(index)
        records                   = contract_rows(records, number) if contract && !records.is_a?(IOStreams::Slice)
        parsing                   = true
        category.parse_records(records, contract: contract) do |record, line_number, record_number|
          # Only the rows of a file are yielded with their numbers, see #records_from.
          record_number           ||= number
          self.processing_at_record = record_number
          parsing                   = false
          yield(record, line_number, record_number)
          parsing                   = true
          number                    = record_number + 1
          self.processing_at_record = number
        end
        # A contract skips each blank row, which is not yielded, so that the last record yielded may not be the last.
        self.processing_at_record = record_number_at(size - 1) + 1 if contract
      rescue IOStreams::Errors::RowError => e
        # A blank row that a contract skipped may be before the record that failed to parse, which the error names. An
        # error that the block raised, such as from another stream that `#perform` reads, names a record of that stream.
        self.processing_at_record = e.record_number if contract && parsing && e.record_number
        raise
      end

      # Returns [true|false] whether an earlier attempt started on this slice, see #processing_at_record, so that the
      # results of the records that it processed may already be in its output, which a retry adds to, rather than
      # processing them again, see #each_unprocessed_record. It does not depend on where the slice points, which a
      # record removed before a retry can move back to its first record, see #delete_record.
      def partly_processed?
        !processing_at_record.nil?
      end

      def_instance_delegators :records, :size

      # Appends the supplied record after the records of this slice. A row added to the rows of a file is numbered as
      # the record after the last, see #record_number_at, so that each row has a record number, see #records_from.
      #
      # Returns self, so that appends can be chained.
      def <<(record)
        if rows?
          records.add(record, record_number: size.zero? ? first_record_number : record_number_at(size - 1) + 1)
        else
          records << record
        end
        self
      end
      def_instance_delegators :record_list, :each, :at

      # Appends the supplied records after the records already in this slice, see Slices#append.
      def append_records(records)
        self.records = self.records + records
      end
      def_instance_delegators :record_list, *(Enumerable.instance_methods - Module.methods)

      # Returns [Integer] the record number of the record currently being processed, see #processing_at_record and
      # #record_number_at: the first record that this slice still holds at or after it.
      # Returns nil when it holds none, such as once every record is processed, or once the record being processed and
      # those after it are removed, see #delete_record.
      def current_record_number
        index = current_index
        record_number_at(index) if index < size || processing_at_record.nil?
      end

      # Returns [Integer] the line of its file that the record currently being processed starts on, see
      # #current_record_number and #line_number_at.
      # Returns nil when it is not a line of a file.
      def current_line_number
        line_number_at(current_index)
      end

      # Returns [Integer] the place of the record currently being processed in this slice, see #current_record_number,
      # counting from 1, such as to replace or remove it, see #replace_record and #delete_record, which take its index:
      # this number less 1. One more than #size when this slice no longer holds it, or a record after it.
      # Returns nil until a worker starts on this slice, see #processing_at_record.
      def processing_record_number
        current_index + 1 if processing_at_record
      end

      # Returns [Integer] the record number of the record at the supplied index, counting from 0: its number in its
      # upload, from 1, without the header row of its file, so that a blank row counts.
      #
      # The rows of a file know their own record numbers, see IOStreams::Slice#record_number_at, which they keep when a
      # record is replaced or removed, see #replace_record and #delete_record, including rows assigned in an Array,
      # which are numbered from #first_record_number when they are assigned, see #records=. Other records are numbered
      # by their place in the slice, from #first_record_number.
      def record_number_at(index)
        number = records.record_number_at(index) if rows_at?(index)
        number || (first_record_number + index)
      end

      # Returns [Integer] the line of its file that the record at the supplied index starts on, counting from 1, as a
      # text editor numbers it, so the header row, and the lines of a quoted value with line breaks, count too, see
      # IOStreams::Slice#line_number_at.
      # Returns nil when the record is not a line of a file, such as a record of a query, of Parquet, of a slice saved
      # by Rocket Job 7, or of rows assigned in an Array, see #records=.
      def line_number_at(index)
        records.line_number_at(index) if rows_at?(index)
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
        records[current_index] if exception && processing_at_record
      end

      # Replaces the record at the supplied index, such as a failed record once it is corrected, see #failed_record. The
      # records keep what they hold besides, such as the header row of the rows of a file, see IOStreams::Slice, and the
      # line and record number of each row. Saved with the slice.
      #
      # Raises IndexError when the slice has no record at the index.
      def replace_record(index, record)
        check_record_index(index)
        records[index] = record
      end

      # Removes the record at the supplied index, rather than every record equal to it. The records keep what they hold
      # besides, see #replace_record. Saved with the slice.
      #
      # Returns the record removed.
      # Raises IndexError when the slice has no record at the index.
      #
      # The slice stays on the record being processed, see #processing_at_record, or the record after it once that one
      # is removed, also for records that are numbered by their place, see #record_number_at.
      def delete_record(index)
        check_record_index(index)
        index  += size if index.negative?
        current = current_index if processing_at_record
        record  = records.delete_at(index)
        point_at_index(index < current ? current - 1 : current) if current
        record
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

      # A slice saved by Rocket Job 7 holds the place in the slice of the record being processed, counting from 1, under
      # "processing_record_number", rather than its record number, see #processing_at_record. Rocket Job 7 numbered
      # each record by its place, from #first_record_number, so the place gives the record number that it meant. The
      # next save of this slice unsets it.
      #
      # Rocket Job 7 saved its records in an Array, see #records_from_document, so their numbers need not be read,
      # which would raise here for records that cannot be read, see #read_records.
      def convert_saved_position
        position = attributes["processing_record_number"]
        return if position.nil?

        self.processing_at_record ||= first_record_number + position - 1
        remove_attribute("processing_record_number")
      end

      # Returns [Integer] the index of the record currently being processed, see #current_record_number: the first
      # record that this slice still holds at or after #processing_at_record, or #size when it holds none.
      def current_index
        processing_at_record ? record_index(processing_at_record) : 0
      end

      # Returns [IOStreams::Slice] the supplied records of this slice, which are not the rows of a file, such as those of
      # `upload_slice`, as rows of the form that they are in, Hashes or Arrays, numbered from the supplied record number,
      # so that an input category reads them through a contract, see #each_unprocessed_record.
      #
      # Raises ArgumentError for other records, such as Strings written without a format, or the lines that Rocket Job 7
      # uploaded, which only the header row that it kept in the category could read.
      def contract_rows(records, record_number)
        format = [Hash, Array].find { |kind| records.all? { |record| record.nil? || record.is_a?(kind) } }
        unless format
          raise(ArgumentError, "Only records that are Hashes or Arrays, such as those of upload_slice, are read through " \
                               "an input contract, not records without a format, such as Strings, see " \
                               "#{self.class.name}##{id}")
        end

        # A record whose values are all nil is kept, as a typed row is, see IOStreams::Slice#blank_rows?.
        IOStreams.slice("rows" => records.to_a, "format" => format.name.downcase, "blank_rows" => false,
                        "record_number" => record_number)
      end

      # Returns [Array|IOStreams::Slice] the records of this slice from the supplied index on, which keep their numbers,
      # see IOStreams::Slice#drop.
      def records_after(index)
        index.zero? ? records : records.drop(index)
      end

      # Points #processing_at_record at the record at the supplied index, unless this slice holds no record there, such
      # as once the record being processed and those after it are removed, when it is left as it is.
      def point_at_index(index)
        self.processing_at_record = record_number_at(index) if index < size
      end

      # Returns [Integer] the index of the first record that this slice holds at or after the supplied record number,
      # see #records_from, or #size when it holds none.
      #
      # Counts the rows before it, rather than copying the rows from it, see #records_from, which finds the same row,
      # since every row of a file has a record number, see #records=.
      def record_index(record_number)
        return (record_number - first_record_number).clamp(0, size) unless rows?

        index = 0
        records.each do |_row, _line_number, number|
          break if number >= record_number

          index += 1
        end
        index
      end

      # Raises ArgumentError when a row of the supplied rows of a file has no record number, see #records=, rather than
      # numbering it, since #first_record_number may not be set yet, such as when it is assigned after the records.
      def check_record_numbers(rows)
        return if rows.each.none? { |_row, _line_number, number| number.nil? }

        raise(ArgumentError, "Each row of a slice of a file needs a record number, so that a retry can resume at it: " \
                             "supply them, such as with IOStreams::Slice.new(rows, record_number: 1, ...)")
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

      # Returns [true|false] whether the slice holds the rows of a file, see IOStreams::Slice, with a row at the supplied
      # index, counting from 0, so that they answer its numbers, see #record_number_at and #line_number_at.
      def rows_at?(index)
        rows? && index >= 0 && index < records.size
      end

      # Returns [Array] the records, or the rows of a file without their numbers, see IOStreams::Slice#rows, which is not
      # an Array, so that the records of every slice are read with the methods of an Array, such as #each and #to_a.
      def record_list
        rows? ? records.rows : records
      end

      # Raises IndexError, as Array#fetch does, when the slice has no record at the supplied index, which counts from
      # the end when it is negative.
      def check_record_index(index)
        count = size
        return if index.is_a?(Integer) && index >= -count && index < count

        raise(IndexError, "index #{index} outside of the records of the slice: #{-count}...#{count}")
      end

      # Returns [IOStreams::Slice] the supplied rows, described as the supplied rows of a file are, such as by their header
      # row and format, see IOStreams::Slice#with_rows, and numbered from #first_record_number, as
      # #record_number_at numbers records, so that each row has a record number, see #records_from.
      def rows_like(slice, rows)
        rows.empty? ? slice.with_rows(rows) : slice.with_rows(rows, record_number: first_record_number)
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

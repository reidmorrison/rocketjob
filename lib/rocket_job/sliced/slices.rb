module RocketJob
  module Sliced
    class Slices
      extend Forwardable
      include Enumerable
      include SemanticLogger::Loggable

      attr_accessor :slice_class, :slice_size, :collection_name
      attr_reader :all

      # Parameters
      #   name: [String]
      #     Name of the collection to create
      #   slice_size: [Integer]
      #     Number of records to store in each slice
      #     Default: 100
      #   slice_class: [class]
      #     Slice class to use to hold records.
      #     Default: RocketJob::Sliced::Slice
      def initialize(collection_name:, slice_class: Sliced::Slice, slice_size: 100)
        @slice_class     = slice_class
        @slice_size      = slice_size
        @collection_name = collection_name

        # Using `Sliced::Slice` avoids having to add `_type` as an index when all slices are the same type anyway.
        @all = Sliced::Slice.with_collection(collection_name)
      end

      def new(params = {})
        slice_class.new(params.merge(collection_name: collection_name))
      end

      def create(params = {})
        slice = new(params)
        slice.save
        slice
      end

      def create!(params = {})
        slice = new(params)
        slice.save!
        slice
      end

      # Returns output slices in the order of their id
      # which is usually the order in which they were written.
      def each(&block)
        all.sort(id: 1).each(&block)
      end

      # Insert a new slice into the collection
      #
      # Returns [Integer] the number of records uploaded
      #
      # Parameters
      #   slice [RocketJob::Sliced::Slice | Array]
      #     The slice to write to the slices collection
      #     If slice is an Array, it will be converted to a Slice before inserting
      #     into the slices collection
      #
      #   input_slice [RocketJob::Sliced::Slice]
      #     The input slice to which this slice corresponds
      #     The id of the input slice is copied across
      #     If the insert results in a duplicate record it is ignored, to support
      #     restarting of jobs that failed in the middle of processing.
      #     A warning is logged that the slice has already been processed.
      #
      # Note:
      #   `slice_size` is not enforced.
      #   However many records are present in the slice will be written as a
      #   single slice to the slices collection
      #
      def insert(slice, input_slice = nil)
        slice = new(records: slice) unless slice.is_a?(Slice)

        # Retain input_slice id in the new output slice
        if input_slice
          slice.id                  = input_slice.id
          slice.first_record_number = input_slice.first_record_number
        end

        begin
          slice.save!
        rescue Mongo::Error::OperationFailure => e
          # Ignore duplicates since it means the job was restarted
          raise(e) unless e.message.include?("E11000")

          logger.warn "Skipped already processed slice# #{slice.id}"
        end
        slice
      end

      def insert_many(slices)
        documents = slices.collect(&:as_document)
        all.collection.insert_many(documents) if documents.present?
      end

      # Append to an existing slice if already present
      def append(slice, input_slice)
        existing_slice = all.where(id: input_slice.id).first
        return insert(slice, input_slice) unless existing_slice

        extra_records          = slice.is_a?(Slice) ? slice.records : slice
        existing_slice.records = existing_slice.records + extra_records
        existing_slice.save!
        existing_slice
      end

      alias << insert

      # Index for find_and_modify only if it is not already present
      def create_indexes
        missing =
          begin
            all.collection.indexes.none? { |i| i["name"] == "state_1__id_1" }
          rescue Mongo::Error::OperationFailure
            true
          end
        all.collection.indexes.create_one({state: 1, _id: 1}, unique: true) if missing
      end

      # Forward additional methods.
      def_instance_delegators :@all, :collection, :count, :delete_all, :first, :find, :last, :nor, :not, :or, :to_a, :where

      # Drop this collection when it is no longer needed
      def drop
        all.collection.drop
      end

      # Forwardable generates invalid warnings on these methods.
      def completed
        all.completed
      end

      def failed
        all.failed
      end

      def queued
        all.queued
      end

      def running
        all.running
      end

      # Mongoid does not apply ordering, add sort
      # rubocop:disable Style/RedundantSort
      def first
        all.sort("_id" => 1).first
      end

      def last
        all.sort("_id" => -1).first
      end

      # rubocop:enable Style/RedundantSort

      # Returns [Array<Struct>] grouped exceptions by class name,
      # and unique exception messages by exception class.
      #
      # Each struct consists of:
      #   class_name: [String]
      #     Exception class name.
      #
      #   count: [Integer]
      #     Number of exceptions with this class.
      #
      #   messages: [Array<String>]
      #     Unique list of error messages.
      def group_exceptions
        result_struct = Struct.new(:class_name, :count, :messages)
        result        = all.collection.aggregate(
          [
            {
              "$match" => {state: "failed"}
            },
            {
              "$group" => {
                _id:      {error_class: "$exception.class_name"},
                messages: {"$addToSet" => "$exception.message"},
                count:    {"$sum" => 1}
              }
            }
          ]
        )
        result.collect do |errors|
          result_struct.new(errors["_id"]["error_class"], errors["count"], errors["messages"])
        end
      end
    end
  end
end

module RocketJob
  class LookupCollection < Mongo::Collection
    # Rapidly upload individual records in batches.
    #
    # Operates directly on a Mongo Collection to avoid the overhead of creating Mongoid objects
    # for each and every row.
    #
    # Example:
    #   lookup_collection(:my_lookup).upload do |io|
    #     io << {id: 123, data: "first record"}
    #     io << {id: 124, data: "second record"}
    #   end
    #
    #   input_category(:my_lookup).find(id: 123).first
    def upload(batch_size: 10_000, &block)
      BatchUploader.upload(batch_size: batch_size, &block)
    end

    # Looks up the value at the specified id.
    # Returns [nil] if no record was found with the supplied id.
    def lookup(id)
      find(id: id).first
    end

    # Internal class for uploading records in batches
    class BatchUploader
      attr_reader :record_count

      def self.upload(collection, **args)
        writer = new(collection, **args)
        yield(writer)
        writer.record_count
      ensure
        writer&.close
      end

      def initialize(collection, batch_size:)
        @batch_size   = batch_size
        @record_count = 0
        @batch_count  = 0
        @documents    = []
        @collection   = collection
      end

      def <<(record)
        raise(ArgumentError, "Record must be a Hash") unless record.is_a?(Hash)

        unless record.key?(:id) || record.key?("id") || record.key?("_id")
          raise(ArgumentError, "Record must include an :id key")
        end

        @documents << record
        @record_count += 1
        @batch_count  += 1
        if @batch_count >= @batch_size
          @collection.insert_many(@documents)
          @documents.clear
          @batch_count = 0
        end

        self
      end

      def close
        @collection.insert_many(@documents) unless @documents.empty?
      end
    end
  end
end

module RocketJob
  module Sliced
    # A slice whose records are saved as one binary value: the BSON document `{"r" => records}`, transformed by
    # #encode_records when it is saved, such as compressed or encrypted, and back by #decode_records when it is read.
    #
    # Each subclass decides how its records are transformed, see CompressedSlice and EncryptedSlice.
    class BinarySlice < ::RocketJob::Sliced::Slice
      private

      def parse_records
        # A slice without records is saved as an empty array, see #serialize_records
        binary = attributes.delete("records")
        return @records = [] unless binary.is_a?(BSON::Binary)

        @records = Hash.from_bson(BSON::ByteBuffer.new(decode_records(binary.data)))["r"]
      end

      def serialize_records
        return [] if @records.nil? || @records.empty?

        # Convert slice of records into a single string
        BSON::Binary.new(encode_records({"r" => records.to_a}.to_bson.to_s))
      end

      # Returns [String] the supplied BSON of the records, transformed to be saved.
      def encode_records(_bson)
        raise(NotImplementedError)
      end

      # Returns [String] the BSON of the records held in the supplied saved data, see #encode_records.
      def decode_records(_data)
        raise(NotImplementedError)
      end
    end
  end
end

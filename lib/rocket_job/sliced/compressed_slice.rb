require "zlib"
module RocketJob
  module Sliced
    # Compress the records within a slice
    class CompressedSlice < ::RocketJob::Sliced::Slice
      private

      def parse_records
        # Convert BSON::Binary to a string
        compressed_str   = attributes.delete("records").data
        decompressed_str = Zlib::Inflate.inflate(compressed_str)
        @records         = Hash.from_bson(BSON::ByteBuffer.new(decompressed_str))["r"]
      end

      def serialize_records
        return [] if @records.nil? || @records.empty?

        # Convert slice of records into a single string
        str = {"r" => records.to_a}.to_bson.to_s

        data = Zlib::Deflate.deflate(str)
        BSON::Binary.new(data)
      end
    end
  end
end

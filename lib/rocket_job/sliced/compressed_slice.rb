require 'zlib'
module RocketJob
  module Sliced
    # Compress the records within a slice
    class CompressedSlice < ::RocketJob::Sliced::Slice
      private

      def parse_records
        records = attributes.delete('records')

        # Convert BSON::Binary to a string
        binary_str = records.data

        str      = Zlib::Inflate.inflate(binary_str)
        @records = Hash.from_bson(BSON::ByteBuffer.new(str))['r']
      end

      def serialize_records
        return [] if @records.nil? || @records.empty?

        # Convert slice of records into a single string
        str = {'r' => records.to_a}.to_bson.to_s

        data = Zlib::Deflate.deflate(str)
        BSON::Binary.new(data)
      end
    end
  end
end

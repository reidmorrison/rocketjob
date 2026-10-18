require "zlib"
module RocketJob
  module Sliced
    # Compress the records within a slice
    class CompressedSlice < ::RocketJob::Sliced::BinarySlice
      private

      def encode_records(bson)
        Zlib::Deflate.deflate(bson)
      end

      def decode_records(data)
        Zlib::Inflate.inflate(data)
      end
    end
  end
end

module RocketJob
  module Sliced
    # This is a specialized output serializer that renders each output slice as a single BZip2 compressed stream.
    # BZip2 allows multiple output streams to be written into a single BZip2 file.
    #
    # Notes:
    # * The `bzip2` linux command line utility supports multiple embedded BZip2 stream,
    #   but some other custom implementations may not. They may only read the first slice and stop.
    # * It is only designed for use on output collections.
    class BZip2OutputSlice < ::RocketJob::Sliced::Slice
      # This is a specialized binary slice for creating BZip2 binary data from each slice
      # that must be downloaded as-is into output files.
      def self.binary_format
        :bz2
      end

      # Compress the supplied records with BZip2
      def self.to_binary(records, record_delimiter = "\n")
        return [] if records.blank?

        lines = Array(records).join(record_delimiter) + record_delimiter
        s     = StringIO.new
        IOStreams::Bzip2::Writer.stream(s) { |io| io.write(lines) }
        s.string
      end

      private

      # Returns [Hash] the BZip2 compressed binary data in binary form when reading back from Mongo.
      def parse_records
        # Convert BSON::Binary to a string
        @records = [attributes.delete("records").data]
      end

      # Returns [BSON::Binary] the records compressed using BZip2 into a string.
      def serialize_records
        # TODO: Make the line terminator configurable
        BSON::Binary.new(self.class.to_binary(@records))
      end
    end
  end
end

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

      # Compress the supplied records with BZip2, as text in the supplied encoding, since they are downloaded as they
      # are. Raises Encoding::UndefinedConversionError for a character that the encoding does not have.
      #
      # Parameters
      #   encoding: [String]
      #     The encoding of the text in the output file, see RocketJob::Category::Output#text_encoding.
      #     Default: nil, which writes UTF-8
      def self.to_binary(records, record_delimiter = "\n", encoding: nil)
        return [] if records.blank?

        lines = Array(records).join(record_delimiter) + record_delimiter
        lines = lines.encode(encoding) if encoding
        s     = StringIO.new
        IOStreams::Bzip2::Writer.stream(s) { |io| io.write(lines) }
        s.string
      end

      # The encoding of the text of the records, which is not saved, see .to_binary.
      attr_accessor :text_encoding

      private

      # Returns [Hash] the BZip2 compressed binary data in binary form when reading back from Mongo.
      def parse_records
        # Convert BSON::Binary to a string
        @records = [attributes.delete("records").data]
      end

      # Returns [BSON::Binary] the records compressed using BZip2 into a string.
      def serialize_records
        # TODO: Make the line terminator configurable
        BSON::Binary.new(self.class.to_binary(@records, encoding: text_encoding))
      end
    end
  end
end

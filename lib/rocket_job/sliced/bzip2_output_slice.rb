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

      # The encoding of the text of the records, see .to_binary. It is saved with the slice, so that records that
      # are appended after the slice is read back, see #append_records, are written in it too.
      # Default: nil, which writes UTF-8
      field :text_encoding, type: String

      # Appends the supplied records. Once this slice has been read back its records are compressed, so the supplied
      # records are compressed after them, as another BZip2 stream, see the notes above.
      def append_records(records)
        return super unless @compressed
        return if records.blank?

        @records = [compressed_records + self.class.to_binary(records, encoding: text_encoding)]
      end

      private

      # Reads back the records as the BZip2 compressed data, which is downloaded as it is.
      def parse_records
        # A slice without records is saved as an empty array, see #serialize_records
        binary = attributes.delete("records")
        return @records = [] unless binary.is_a?(BSON::Binary)

        @compressed = true
        @records    = [read_binary(binary.data)]
      end

      # Returns [BSON::Binary] the records compressed using BZip2 into a string.
      def serialize_records
        return [] if records.empty?

        BSON::Binary.new(write_binary(compressed_records))
      end

      # Returns [String] the records compressed with BZip2: as they were read back, or compressed now.
      def compressed_records
        # TODO: Make the line terminator configurable
        @compressed ? records.join : self.class.to_binary(records, encoding: text_encoding)
      end

      # Returns [String] the compressed records held in the supplied saved data, see #write_binary.
      def read_binary(data)
        data
      end

      # Returns [String] the data to save that holds the supplied compressed records.
      def write_binary(compressed)
        compressed
      end
    end
  end
end

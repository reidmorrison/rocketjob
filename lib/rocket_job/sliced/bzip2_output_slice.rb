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

      # Returns [Hash] the attributes that write the text of the slice in the supplied format and encoding, see .to_binary,
      # which the slice saves.
      def self.binary_attributes(format: nil, encoding: nil)
        {text_format: format&.to_s, text_encoding: encoding}.compact
      end

      # Compress the supplied records with BZip2, since they are downloaded as they are, as IOStreams writes their lines
      # in the supplied format and encoding, as it writes an output file: in the format's own encoding, such as ASCII
      # for fixed width, unless an encoding is supplied, and otherwise UTF-8. Raises
      # Encoding::UndefinedConversionError for a character that the encoding does not have.
      #
      # Parameters
      #   text_format: [String]
      #     The format of the lines, such as "fixed", see RocketJob::Category::Output#text_settings.
      #     Default: nil
      #
      #   text_encoding: [String]
      #     The encoding of the text in the output file, such as "Windows-1252".
      #     Default: nil
      def self.to_binary(records, text_format: nil, text_encoding: nil)
        return [] if records.blank?

        # The rows of a slice of a file, see IOStreams::Slice, are its lines.
        records = records.rows if records.is_a?(IOStreams::Slice)
        # Binary, since compressed data is bytes, so that it can follow the compressed records of a slice read back.
        s       = StringIO.new("".b)
        stream  = IOStreams.stream(s).stream(:bz2)
        stream.format(text_format) if text_format
        stream.encoding("#{text_encoding}:UTF-8") if text_encoding
        # Each record is a line of its text, as Array#join writes it, a nested Array a line for each of its values.
        stream.writer(:line) { |io| Array(records).flatten.each { |record| io << record.to_s } }
        s.string
      end

      # The format and encoding that the text of the records is written in, see .to_binary. They are saved with the
      # slice, so that records that are appended after the slice is read back, see #append_records, are written as
      # those before them.
      # Default: nil, which writes UTF-8
      field :text_format, type: String
      field :text_encoding, type: String

      # Appends the supplied records. Once this slice has been read back its records are compressed, so the supplied
      # records are compressed after them, as another BZip2 stream, see the notes above.
      def append_records(records)
        return super unless @compressed
        return if records.blank?

        @records = [compressed_records + self.class.to_binary(records, text_format: text_format, text_encoding: text_encoding)]
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
        @compressed ? records.join : self.class.to_binary(records, text_format: text_format, text_encoding: text_encoding)
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

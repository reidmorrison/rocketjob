require "tempfile"

module RocketJob
  module Sliced
    class Output < Slices
      # Parameters
      #   text_encoding: [String|Proc]
      #     The encoding of the text in the output file, or a Proc that returns it when it is needed, so that it
      #     can change after this collection is created, see RocketJob::Category::Output#text_encoding.
      #     Default: nil, which writes UTF-8
      #
      #   See Slices#initialize for the other parameters.
      def initialize(text_encoding: nil, **)
        super(**)
        @text_encoding = text_encoding
      end

      # Returns [String] the encoding of the text that a binary slice, such as BZip2OutputSlice, writes its records
      # in, see Slice.binary_format, or nil for UTF-8. Other slices keep their records as UTF-8, which is converted
      # when they are downloaded.
      def text_encoding
        @text_encoding.respond_to?(:call) ? @text_encoding.call : @text_encoding
      end

      # Returns [RocketJob::Sliced::Slice] a new slice, which writes its records in #text_encoding when it is binary.
      def new(params = {})
        encoding = text_encoding if binary_format
        super(encoding ? params.merge(text_encoding: encoding) : params)
      end

      # Returns [Symbol] the binary format of the slices, such as :bz2, which are downloaded as they are, or nil
      # when they hold records, see Slice.binary_format.
      def binary_format
        slice_class.binary_format
      end

      # Returns [String] the supplied header line in the binary format of the slices, see #binary_format, and in
      # #text_encoding, to download in front of them.
      def binary_header(header_line)
        slice_class.to_binary(header_line, encoding: text_encoding)
      end

      def download(header_line: nil)
        raise(ArgumentError, "Block is mandatory") unless block_given?

        # Write the header line
        yield(header_line) if header_line

        # Call the supplied block for every record returned
        record_count = 0
        each do |slice|
          # TODO: Add slice_id to named tags to aid problem determination
          slice.each do |record|
            record_count += 1
            yield(record)
          end
        end
        record_count
      end
    end
  end
end

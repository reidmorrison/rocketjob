require "tempfile"

module RocketJob
  module Sliced
    class Output < Slices
      # Parameters
      #   binary_text: [Proc]
      #     Returns how the slices of a binary format write their text, see RocketJob::Category::Output#binary_text, when
      #     it is needed, so that it can change after this collection is created.
      #
      #   See Slices#initialize for the other parameters.
      def initialize(binary_text: nil, **)
        super(**)
        @binary_text = binary_text
      end

      # Returns [Hash] how the slices of a binary format, such as BZip2OutputSlice, write their text, see
      # Slice.binary_format: its `text_format` and `text_encoding`, which each such slice saves. Other slices keep their
      # records as UTF-8, which is converted when they are downloaded.
      def binary_text
        @binary_text&.call || {}
      end

      # Returns [RocketJob::Sliced::Slice] a new slice, which writes its text as #binary_text says when it is binary.
      def new(params = {})
        binary_format ? super(binary_text.merge(params)) : super
      end

      # Returns [Symbol] the binary format of the slices, such as :bz2, which are downloaded as they are, or nil
      # when they hold records, see Slice.binary_format.
      def binary_format
        slice_class.binary_format
      end

      # Returns [String] the supplied header line in the binary format of the slices, see #binary_format, written as
      # #binary_text says, to download in front of them.
      def binary_header(header_line)
        slice_class.to_binary(header_line, **binary_text)
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

require "tempfile"

module RocketJob
  module Sliced
    class Output < Slices
      # Parameters
      #   text_settings: [Proc]
      #     Returns the format and encoding that the text of the output file is written in, see
      #     RocketJob::Category::Output#text_settings, when it is needed, so that they can change after this collection
      #     is created.
      #
      #   See Slices#initialize for the other parameters.
      def initialize(text_settings: nil, **)
        super(**)
        @text_settings = text_settings
      end

      # Returns [Hash] the format and encoding of the text of the output file, as `format:` and `encoding:`, see
      # #initialize.
      def text_settings
        @text_settings&.call || {}
      end

      # Returns [RocketJob::Sliced::Slice] a new slice, which writes its text in the format and encoding of the output
      # file when it is binary, see Slice.binary_format, as the slice class says, see Slice.binary_attributes.
      def new(params = {})
        binary_format ? super(slice_class.binary_attributes(**text_settings).merge(params)) : super
      end

      # Returns [Symbol] the binary format of the slices, such as :bz2, which are downloaded as they are, or nil
      # when they hold records, see Slice.binary_format.
      def binary_format
        slice_class.binary_format
      end

      # Returns [String] the supplied header line in the binary format of the slices, see #binary_format, in the format
      # and encoding of the output file, see #text_settings, to download in front of them.
      def binary_header(header_line)
        slice_class.to_binary(header_line, **slice_class.binary_attributes(**text_settings).symbolize_keys)
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

require "tempfile"

module RocketJob
  module Sliced
    class Output < Slices
      # The encoding of the text that a binary slice, such as BZip2OutputSlice, writes its records in, see
      # RocketJob::Category::Output#text_encoding. Other slices keep their records as UTF-8.
      attr_reader :text_encoding

      # Parameters
      #   text_encoding: [String]
      #     See #text_encoding.
      #     Default: nil, which writes UTF-8
      #
      #   See Slices#initialize for the other parameters.
      def initialize(text_encoding: nil, **)
        super(**)
        @text_encoding = text_encoding
      end

      # Returns [RocketJob::Sliced::Slice] a new slice, which writes its records in #text_encoding when it is binary.
      def new(params = {})
        slice = super
        slice.text_encoding = text_encoding if slice.respond_to?(:text_encoding=)
        slice
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

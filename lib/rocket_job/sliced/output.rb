require 'tempfile'

module RocketJob
  module Sliced
    class Output < Slices
      def download(header_line: nil)
        raise(ArgumentError, 'Block is mandatory') unless block_given?

        # Write the header line
        yield(header_line) if header_line

        # Call the supplied block for every record returned
        record_count = 0
        each do |slice|
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

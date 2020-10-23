module RocketJob
  module Sliced
    # This is a specialized output serializer that renders each output slice as a single BZip2 compressed stream.
    # BZip2 allows multiple output streams to be written into a single BZip2 file.
    #
    # Notes:
    # * The `bzip2` linux command line utility supports multiple embedded BZip2 stream,
    #   but some other custom implementations may not. They may only read the first slice and stop.
    # * It is only designed for use on output collections.
    #
    # To download the output when using this slice:
    #
    #   # Download the binary BZip2 streams into a single file
    #   IOStreams.path(output_file_name).stream(:none).writer do |io|
    #     job.download { |slice| io << slice[:binary] }
    #   end
    class BZip2OutputSlice < ::RocketJob::Sliced::Slice
      # This is a specialized binary slice for creating binary data from each slice
      # that must be downloaded as-is into output files.
      def self.binary?
        true
      end

      private

      def parse_records
        records = attributes.delete("records")

        # Convert BSON::Binary to a string
        @records = [{binary: records.data}]
      end

      def serialize_records
        return [] if @records.nil? || @records.empty?

        lines = records.to_a.join("\n") + "\n"
        s = StringIO.new
        IOStreams::Bzip2::Writer.stream(s) { |io| io.write(lines) }
        BSON::Binary.new(s.string)
      end
    end
  end
end

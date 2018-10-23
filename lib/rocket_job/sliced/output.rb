require 'tempfile'

module RocketJob
  module Sliced
    class Output < Slices
      # Write this output collection to the specified file/io stream
      #
      # Returns [Integer] the number of records returned from the collection
      #
      # Parameters
      #   file_name_or_io [String|IO]
      #     The file_name of the file to write to, or an IO Stream that implements
      #     #write.
      #
      #   options:
      #     streams [Symbol|Array]
      #       The formats/streams that be used to convert the data whilst it is
      #       being written.
      #       When nil, `file_name_or_io` will be inspected to try and determine what
      #       streams should be applied.
      #       Default: nil
      #
      #     Any other option that can be supplied to IOStreams::Line::Writer
      #
      # Stream types / extensions supported:
      #   .zip       Zip File                                   [ :zip ]
      #   .gz, .gzip GZip File                                  [ :gzip ]
      #   .enc       File Encrypted using symmetric encryption  [ :enc ]
      #
      # When a file is encrypted, it may also be compressed:
      #   .zip.enc  [ :zip, :enc ]
      #   .gz.enc   [ :gz,  :enc ]
      #
      # Example: Zip
      #   # Since csv is not known to RocketJob it is ignored
      #   job.output.download('myfile.csv.zip')
      #
      # Example: Encrypted Zip
      #   job.output.download('myfile.csv.zip.enc')
      #
      # Example: Explicitly set the streams
      #   job.output.download('myfile.ze', streams: [:zip, :enc])
      #
      # Example: Supply custom options
      #   job.output.download('myfile.csv.enc', streams: [enc: { compress: true }])
      #
      # Example: Supply custom options
      #   job.output.download('myfile.csv.zip', streams: [ zip: { zip_file_name: 'myfile.csv' } ])
      #
      # Example: Extract streams from filename but write to a temp file
      #   t = Tempfile.new('my_project')
      #   job.output.download(t.to_path, file_name: 'myfile.gz.enc')
      #
      # Example: Add a header and/or trailer record to the downloaded file:
      #   IOStreams.writer('/tmp/file.txt.gz') do |writer|
      #     writer << "Header\n"
      #     job.download do |line|
      #       writer << line
      #     end
      #     writer << "Trailer\n"
      #   end
      #
      # Notes:
      # - The records are returned in '_id' order. Usually this is the order in
      #   which the records were originally loaded.
      def download(file_name_or_io = nil, header_line: nil, **args)
        raise(ArgumentError, 'Either file_name_or_io, or a block must be supplied') unless file_name_or_io || block_given?

        record_count = 0

        if block_given?
          # Write the header line
          yield(header_line) if header_line

          # Call the supplied block for every record returned
          each do |slice|
            slice.each do |record|
              record_count += 1
              yield(record)
            end
          end
        else
          IOStreams.line_writer(file_name_or_io, **args) do |io|
            # Write the header line
            io << header_line if header_line

            each do |slice|
              slice.each do |record|
                record_count += 1
                io << record
              end
            end
          end
        end
        record_count
      end
    end
  end
end

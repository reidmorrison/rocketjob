require "active_support/concern"

module RocketJob
  module Batch
    # IO methods for sliced jobs
    module IO
      extend ActiveSupport::Concern

      # Returns [RocketJob::Sliced::Input] input collection for holding input slices
      #
      # Parameters:
      #   category [Symbol]
      #     The name of the category to access or upload data into
      #     Default: None ( Uses the single default input collection for this job )
      #     Validates: This value must be one of those listed in #input_categories
      def input(category = :main)
        category = input_categories[category] unless category.is_a?(Category)

        (@inputs ||= {})[category] ||= RocketJob::Sliced.factory(:input, category, self)
      end

      # Returns [RocketJob::Sliced::Output] output collection for holding output slices
      # Returns nil if no output is being collected
      #
      # Parameters:
      #   category [Symbol]
      #     The name of the category to access or download data from
      #     Default: None ( Uses the single default output collection for this job )
      #     Validates: This value must be one of those listed in #output_categories
      def output(category = :main)
        category = output_categories[category] unless category.is_a?(Category)

        (@outputs ||= {})[category] ||= RocketJob::Sliced.factory(:output, category, self)
      end

      # Upload the supplied file, io, IOStreams::Path, or IOStreams::Stream.
      #
      # Returns [Integer] the number of records uploaded.
      #
      # Parameters
      #   stream [String | IO | IOStreams::Path | IOStreams::Stream]
      #     Full path and file name to stream into the job,
      #     Or, an IO Stream that responds to: :read
      #     Or, an IOStreams path such as IOStreams::Paths::File, or IOStreams::Paths::S3
      #
      #   delimiter[String]
      #     Line / Record delimiter to use to break the stream up into records
      #       Any string to break the stream up by
      #       The records when saved will not include this delimiter
      #     Default: nil
      #       Automatically detect line endings and break up by line
      #       Searches for the first "\r\n" or "\n" and then uses that as the
      #       delimiter for all subsequent records
      #
      #   stream_mode: [:line | :array | :hash]
      #     :line
      #       Uploads the file a line (String) at a time for processing by workers.
      #     :array
      #       Parses each line from the file as an Array and uploads each array for processing by workers.
      #     :hash
      #       Parses each line from the file into a Hash and uploads each hash for processing by workers.
      #     See IOStreams::Stream#each.
      #
      # Example:
      #   # Load plain text records from a file
      #   job.upload('hello.csv')
      #
      # Example:
      #   # Load plain text records from a file, stripping all non-printable characters,
      #   # as well as any characters that cannot be converted to UTF-8
      #   path = IOStreams.path('hello.csv').option(:encode, cleaner: :printable, replace: '')
      #   job.upload(path)
      #
      # Example: Zip
      #   # Since csv is not known to RocketJob it is ignored
      #   job.upload('myfile.csv.zip')
      #
      # Example: Encrypted Zip
      #   job.upload('myfile.csv.zip.enc')
      #
      # Example: Explicitly set the streams
      #   path = IOStreams.path('myfile.ze').stream(:encode, encoding: 'UTF-8').stream(:zip).stream(:enc)
      #   job.upload(path)
      #
      # Example: Supply custom options
      #   path = IOStreams.path('myfile.csv.enc').option(:enc, compress: false).option(:encode, encoding: 'UTF-8')
      #   job.upload(path)
      #
      # Example: Read from a tempfile and use the original file name to determine which streams to apply
      #   temp_file = Tempfile.new('my_project')
      #   temp_file.write(gzip_and_encrypted_data)
      #   stream = IOStreams.stream(temp_file).file_name('myfile.gz.enc')
      #   job.upload(stream)
      #
      # Example: Upload by writing records one at a time to the upload stream
      #   job.upload do |writer|
      #     10.times { |i| writer << i }
      #   end
      #
      # Notes:
      # * Only call from one thread at a time against a single instance of this job.
      # * The record_count for the job is set to the number of records returned by the arel.
      # * If an exception is raised while uploading data, the input collection is cleared out
      #   so that if a job is retried during an upload failure, data is not duplicated.
      # * By default all data read from the file/stream is converted into UTF-8 before being persisted. This
      #   is recommended since Mongo only supports UTF-8 strings.
      # * When zip format, the Zip file/stream must contain only one file, the first file found will be
      #   loaded into the job
      # * If an io stream is supplied, it is read until it returns nil.
      # * Only use this method for UTF-8 data, for binary data use #input_slice or #input_records.
      # * CSV parsing is slow, so it is usually left for the workers to do.
      def upload(stream = nil, file_name: nil, category: :main, stream_mode: :line, on_first: nil, **args, &block)
        raise(ArgumentError, "Either stream, or a block must be supplied") unless stream || block

        stream_mode = stream_mode.to_sym
        # Backward compatibility with existing v4 jobs
        stream_mode = :array if stream_mode == :row
        stream_mode = :hash if stream_mode == :record

        count             =
          if block
            input(category).upload(on_first: on_first, &block)
          else
            path                  = IOStreams.new(stream)
            path.file_name        = file_name if file_name
            self.upload_file_name = path.file_name
            input(category).upload(on_first: on_first) do |io|
              path.each(stream_mode, **args) { |line| io << line }
            end
          end
        self.record_count = (record_count || 0) + count
        count
      end

      # Upload results from an Arel into RocketJob::SlicedJob.
      #
      # Params
      #   column_names
      #     When a block is not supplied, supply the names of the columns to be returned
      #     and uploaded into the job
      #     These columns are automatically added to the select list to reduce overhead
      #
      # If a Block is supplied it is passed the model returned from the database and should
      # return the work item to be uploaded into the job.
      #
      # Returns [Integer] the number of records uploaded
      #
      # Example: Upload id's for all users
      #   arel = User.all
      #   job.upload_arel(arel)
      #
      # Example: Upload selected user id's
      #   arel = User.where(country_code: 'US')
      #   job.upload_arel(arel)
      #
      # Example: Upload user_name and zip_code
      #   arel = User.where(country_code: 'US')
      #   job.upload_arel(arel, :user_name, :zip_code)
      #
      # Notes:
      # * Only call from one thread at a time against a single instance of this job.
      # * The record_count for the job is set to the number of records returned by the arel.
      # * If an exception is raised while uploading data, the input collection is cleared out
      #   so that if a job is retried during an upload failure, data is not duplicated.
      def upload_arel(arel, *column_names, category: :main, &block)
        count             = input(category).upload_arel(arel, *column_names, &block)
        self.record_count = (record_count || 0) + count
        count
      end

      # Upload the result of a MongoDB query to the input collection for processing
      # Useful when an entire MongoDB collection, or part thereof needs to be
      # processed by a job.
      #
      # Returns [Integer] the number of records uploaded
      #
      # If a Block is supplied it is passed the document returned from the
      # database and should return a record for processing
      #
      # If no Block is supplied then the record will be the :fields returned
      # from MongoDB
      #
      # Note:
      #   This method uses the collection and not the MongoMapper document to
      #   avoid the overhead of constructing a Model with every document returned
      #   by the query
      #
      # Note:
      #   The Block must return types that can be serialized to BSON.
      #   Valid Types: Hash | Array | String | Integer | Float | Symbol | Regexp | Time
      #   Invalid: Date, etc.
      #
      # Example: Upload document ids
      #   criteria = User.where(state: 'FL')
      #   job.record_count = job.upload_mongo_query(criteria)
      #
      # Example: Upload just the supplied column
      #   criteria = User.where(state: 'FL')
      #   job.record_count = job.upload_mongo_query(criteria, :zip_code)
      #
      # Notes:
      # * Only call from one thread at a time against a single instance of this job.
      # * The record_count for the job is set to the number of records returned by the monqo query.
      # * If an exception is raised while uploading data, the input collection is cleared out
      #   so that if a job is retried during an upload failure, data is not duplicated.
      def upload_mongo_query(criteria, *column_names, category: :main, &block)
        count             = input(category).upload_mongo_query(criteria, *column_names, &block)
        self.record_count = (record_count || 0) + count
        count
      end

      # Upload sliced range of integer requests as arrays of start and end ids.
      #
      # Returns [Integer] last_id - start_id + 1.
      #
      # Uploads one range per slice so that the response can return multiple records
      # for each slice processed
      #
      # Example
      #   job.slice_size = 100
      #   job.upload_integer_range(200, 421)
      #
      #   # Equivalent to calling:
      #   job.input.insert([200,299])
      #   job.input.insert([300,399])
      #   job.input.insert([400,421])
      #
      # Notes:
      # * Only call from one thread at a time against a single instance of this job.
      # * The record_count for the job is set to: last_id - start_id + 1.
      # * If an exception is raised while uploading data, the input collection is cleared out
      #   so that if a job is retried during an upload failure, data is not duplicated.
      def upload_integer_range(start_id, last_id, category: :main)
        input(category).upload_integer_range(start_id, last_id)
        count             = last_id - start_id + 1
        self.record_count = (record_count || 0) + count
        count
      end

      # Upload sliced range of integer requests as an arrays of start and end ids
      # starting with the last range first
      #
      # Returns [Integer] last_id - start_id + 1.
      #
      # Uploads one range per slice so that the response can return multiple records
      # for each slice processed.
      # Useful for when the highest order integer values should be processed before
      # the lower integer value ranges. For example when processing every record
      # in a database based on the id column
      #
      # Example
      #   job.slice_size = 100
      #   job.upload_integer_range_in_reverse_order(200, 421)
      #
      #   # Equivalent to calling:
      #   job.input.insert([400,421])
      #   job.input.insert([300,399])
      #   job.input.insert([200,299])
      #
      # Notes:
      # * Only call from one thread at a time against a single instance of this job.
      # * The record_count for the job is set to: last_id - start_id + 1.
      # * If an exception is raised while uploading data, the input collection is cleared out
      #   so that if a job is retried during an upload failure, data is not duplicated.
      def upload_integer_range_in_reverse_order(start_id, last_id, category: :main)
        input(category).upload_integer_range_in_reverse_order(start_id, last_id)
        count             = last_id - start_id + 1
        self.record_count = (record_count || 0) + count
        count
      end

      # Upload the supplied slices for processing by workers
      #
      # Updates the record_count after adding the records
      #
      # Returns [Integer] the number of records uploaded
      #
      # Parameters
      #   `slice` [ Array<Hash | Array | String | Integer | Float | Symbol | Regexp | Time> ]
      #     All elements in `array` must be serializable to BSON
      #     For example the following types are not supported: Date
      #
      # Note:
      #   The caller should honor `:slice_size`, the entire slice is loaded as-is.
      #
      # Note:
      #   Not thread-safe. Only call from one thread at a time
      def upload_slice(slice)
        input.insert(slice)
        count             = slice.size
        self.record_count = (record_count || 0) + count
        count
      end

      # Download the output data into the supplied file, io, IOStreams::Path, or IOStreams::Stream.
      # Returns [Integer] the number of records / lines downloaded.
      #
      # Parameters
      #   stream [String | IO | IOStreams::Path | IOStreams::Stream]
      #     Full path and file name to stream into the job,
      #     Or, an IO stream that responds to: :write
      #     Or, an IOStreams path such as IOStreams::Paths::File, or IOStreams::Paths::S3
      #
      # Example: Zip
      #   # Since csv is not known to RocketJob it is ignored
      #   job.download('myfile.csv.zip')
      #
      # Example: Encrypted Zip
      #   job.download('myfile.csv.zip.enc')
      #
      # Example: Explicitly set the streams
      #   path = IOStreams.path('myfile.ze').stream(:zip).stream(:enc)
      #   job.download(path)
      #
      # Example: Supply custom options
      #   path = IOStreams.path('myfile.csv.enc').option(:enc, compress: false)
      #   job.download(path)
      #
      # Example: Supply custom options. Set the file name within the zip file.
      #   path = IOStreams.path('myfile.csv.zip').option(:zip, zip_file_name: 'myfile.csv')
      #   job.download(path)
      #
      # Example: Download into a tempfile, or stream, using the original file name to determine the streams to apply:
      #   tempfile = Tempfile.new('my_project')
      #   stream = IOStreams.stream(tempfile).file_name('myfile.gz.enc')
      #   job.download(stream)
      #
      # Example: Add a header and/or trailer record to the downloaded file:
      #   IOStreams.path('/tmp/file.txt.gz').writer do |writer|
      #     writer << "Header\n"
      #     job.download do |line|
      #       writer << line + "\n"
      #     end
      #     writer << "Trailer\n"
      #   end
      #
      # Example: Add a header and/or trailer record to the downloaded file, letting the line writer add the line breaks:
      #   IOStreams.path('/tmp/file.txt.gz').writer(:line) do |writer|
      #     writer << "Header"
      #     job.download do |line|
      #       writer << line
      #     end
      #     writer << "Trailer"
      #   end
      #
      # Notes:
      # - The records are returned in '_id' order. Usually this is the order in
      #   which the records were originally loaded.
      def download(stream = nil, category: :main, header_line: nil, **args, &block)
        raise "Cannot download incomplete job: #{id}. Currently in state: #{state}-#{sub_state}" if rocket_job_processing?

        return output(category).download(header_line: header_line, &block) if block

        output_collection = output(category)

        if output_collection.binary?
          IOStreams.new(stream).stream(:none).writer(**args) do |io|
            raise(ArgumenError, "A `header_line` is not supported with binary output collections") if header_line

            output_collection.download { |record| io << record[:binary] }
          end
        else
          IOStreams.new(stream).writer(:line, **args) do |io|
            output_collection.download(header_line: header_line) { |record| io << record }
          end
        end
      end

      # Writes the supplied result, Batch::Result or Batch::Results to the relevant collections.
      #
      # If a block is supplied, the block is supplied with a writer that should be used to
      # accumulate the results.
      #
      # Examples
      #
      # job.write_output('hello world')
      #
      # job.write_output do |writer|
      #   writer << 'hello world'
      # end
      #
      # job.write_output do |writer|
      #   result = RocketJob::Batch::Results
      #   result << RocketJob::Batch::Result.new(:main, 'hello world')
      #   result << RocketJob::Batch::Result.new(:errors, 'errors')
      #   writer << result
      # end
      #
      # result = RocketJob::Batch::Results
      # result << RocketJob::Batch::Result.new(:main, 'hello world')
      # result << RocketJob::Batch::Result.new(:errors, 'errors')
      # job.write_output(result)
      def write_output(result = nil, input_slice = nil, &block)
        if block
          RocketJob::Sliced::Writer::Output.collect(self, input_slice, &block)
        else
          raise(ArgumentError, "result parameter is required when no block is supplied") unless result

          RocketJob::Sliced::Writer::Output.collect(self, input_slice) { |writer| writer << result }
        end
      end
    end
  end
end

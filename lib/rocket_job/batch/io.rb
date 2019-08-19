require 'active_support/concern'

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
        raise "Category #{category.inspect}, must be registered in input_categories: #{input_categories.inspect}" unless input_categories.include?(category) || (category == :main)

        collection_name = "rocket_job.inputs.#{id}"
        collection_name << ".#{category}" unless category == :main

        (@inputs ||= {})[category] ||= RocketJob::Sliced::Input.new(slice_arguments(collection_name))
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
        raise "Category #{category.inspect}, must be registered in output_categories: #{output_categories.inspect}" unless output_categories.include?(category) || (category == :main)

        collection_name = "rocket_job.outputs.#{id}"
        collection_name << ".#{category}" unless category == :main

        (@outputs ||= {})[category] ||= RocketJob::Sliced::Output.new(slice_arguments(collection_name))
      end

      # Upload the supplied file_name or stream.
      #
      # Returns [Integer] the number of records uploaded.
      #
      # Parameters
      #   file_name_or_io [String | IO]
      #     Full path and file name to stream into the job,
      #     Or, an IO Stream that responds to: :read
      #
      #   streams [Symbol|Array]
      #     Streams to convert the data whilst it is being read.
      #     When nil, the file_name extensions will be inspected to determine what
      #     streams should be applied.
      #     Default: nil
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
      #   buffer_size [Integer]
      #     Size of the blocks when reading from the input file / stream.
      #     Default: 65536 ( 64K )
      #
      #   encoding: [String|Encoding]
      #     Encode returned data with this encoding.
      #     'US-ASCII':   Original 7 bit ASCII Format
      #     'ASCII-8BIT': 8-bit ASCII Format
      #     'UTF-8':      UTF-8 Format
      #     Etc.
      #     Default: 'UTF-8'
      #
      #   encode_replace: [String]
      #     The character to replace with when a character cannot be converted to the target encoding.
      #     nil: Don't replace any invalid characters. Encoding::UndefinedConversionError is raised.
      #     Default: nil
      #
      #   encode_cleaner: [nil|symbol|Proc]
      #     Cleanse data read from the input stream.
      #     nil:           No cleansing
      #     :printable Cleanse all non-printable characters except \r and \n
      #     Proc/lambda    Proc to call after every read to cleanse the data
      #     Default: :printable
      #
      #   stream_mode: [:line | :row | :record]
      #     :line
      #       Uploads the file a line (String) at a time for processing by workers.
      #     :row
      #       Parses each line from the file as an Array and uploads each array for processing by workers.
      #     :record
      #       Parses each line from the file into a Hash and uploads each hash for processing by workers.
      #     See IOStream#each_line, IOStream#each_row, and IOStream#each_record.
      #
      # Example:
      #   # Load plain text records from a file
      #   job.input.upload('hello.csv')
      #
      # Example:
      #   # Load plain text records from a file, stripping all non-printable characters,
      #   # as well as any characters that cannot be converted to UTF-8
      #   job.input.upload('hello.csv', encode_cleaner: :printable, encode_replace: '')
      #
      # Example: Zip
      #   # Since csv is not known to RocketJob it is ignored
      #   job.input.upload('myfile.csv.zip')
      #
      # Example: Encrypted Zip
      #   job.input.upload('myfile.csv.zip.enc')
      #
      # Example: Explicitly set the streams
      #   job.input.upload('myfile.ze', streams: [:zip, :enc])
      #
      # Example: Supply custom options
      #   job.input.upload('myfile.csv.enc', streams: :enc])
      #
      # Example: Extract streams from filename but write to a temp file
      #   streams = IOStreams.streams_for_file_name('myfile.gz.enc')
      #   t = Tempfile.new('my_project')
      #   job.input.upload(t.to_path, streams: streams)
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
      def upload(file_name_or_io = nil, file_name: nil, category: :main, **args, &block)
        if file_name
          self.upload_file_name = file_name
        elsif file_name_or_io.is_a?(String)
          self.upload_file_name = file_name_or_io
        end
        count             = input(category).upload(file_name_or_io, file_name: file_name, **args, &block)
        self.record_count = (record_count || 0) + count
        count
      rescue StandardError => exc
        input(category).delete_all
        raise(exc)
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
      rescue StandardError => exc
        input(category).delete_all
        raise(exc)
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
      rescue StandardError => exc
        input(category).delete_all
        raise(exc)
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
      rescue StandardError => exc
        input(category).delete_all
        raise(exc)
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
      rescue StandardError => exc
        input(category).delete_all
        raise(exc)
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

      # Download the output data into the supplied file_name or stream
      #
      # Parameters
      #   file_name_or_io [String|IO]
      #     The file_name of the file to write to, or an IO Stream that implements #write.
      #
      #   options:
      #     category [Symbol]
      #       The category of output to download
      #       Default: :main
      #
      # See RocketJob::Sliced::Output#download for remaining options
      #
      # Returns [Integer] the number of records downloaded
      def download(file_name_or_io = nil, category: :main, **args, &block)
        raise "Cannot download incomplete job: #{id}. Currently in state: #{state}-#{sub_state}" if rocket_job_processing?

        output(category).download(file_name_or_io, **args, &block)
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
          raise(ArgumentError, 'result parameter is required when no block is supplied') unless result
          RocketJob::Sliced::Writer::Output.collect(self, input_slice) { |writer| writer << result }
        end
      end

      private

      def slice_arguments(collection_name)
        {
          collection_name: collection_name,
          slice_size:      slice_size
        }
      end
    end
  end
end

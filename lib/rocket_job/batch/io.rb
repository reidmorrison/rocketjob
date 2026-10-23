require "active_support/concern"

module RocketJob
  module Batch
    # IO methods for sliced jobs
    module IO
      extend ActiveSupport::Concern

      # Returns [RocketJob::Sliced::Input] input collection for holding input slices
      #
      # Parameters:
      #   category [Symbol|RocketJob::Category::Input]
      #     The category or the name of the category to access or upload data into
      #     Default: None ( Uses the single default input collection for this job )
      #     Validates: This value must be one of those listed in #input_categories
      def input(category = :main)
        category = input_category(category)

        (@inputs ||= {})[category.name] ||= category.data_store(self)
      end

      # Returns [RocketJob::Sliced::Output] output collection for holding output slices
      # Returns nil if no output is being collected
      #
      # Parameters:
      #   category [Symbol|RocketJob::Category::Input]
      #     The category or the name of the category to access or download data from
      #     Default: None ( Uses the single default output collection for this job )
      #     Validates: This value must be one of those listed in #output_categories
      def output(category = :main)
        category = output_category(category)

        (@outputs ||= {})[category.name] ||= category.data_store(self)
      end

      # Rapidly upload individual records in batches.
      #
      # Operates directly on a Mongo Collection to avoid the overhead of creating Mongoid objects
      # for each and every row.
      #
      #   input_category(:my_lookup).find(id: 123).first
      #
      # Lookup collection.
      #
      # Upload side / secondary lookup tables that can be accessed during job processing.
      #
      # Example:
      #   lookup_collection(:my_lookup).upload do |io|
      #     io << {id: 123, data: "first record"}
      #     io << {id: 124, data: "second record"}
      #   end
      #
      # Parameters:
      #   category [Symbol|RocketJob::Category::Input]
      #     The category or the name of the category to access or download data from
      #     Default: None ( Uses the single default output collection for this job )
      #     Validates: This value must be one of those listed in #input_categories
      # def lookup_collection(category = :main)
      #   category = input_category(category) unless category.is_a?(Category::Input)
      #
      #   collection = (@lookup_collections ||= {})[category.name]
      #
      #   unless collection
      #     collection_name = "rocket_job.inputs.#{id}"
      #     collection_name << ".#{category.name}" unless category.name == :main
      #
      #     @lookup_collections[category.name] ||=
      #       LookupCollection.new(Sliced::Slice.collection.database, collection_name)
      #   end
      # end

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
      #   validate_rows: [true | false]
      #     true to parse each line of the file in the input category's format while it is uploaded, so that a file
      #     with a line that cannot be read, or with a value that is not valid, uploads nothing. The lines are still
      #     uploaded as they are, and the workers parse them.
      #     Raises ArgumentError when true for an input category without a format, or for a query, a range or a block,
      #     which upload values rather than the lines of a file, and when supplied with `stream_mode:`. False is
      #     accepted for each, since it validates nothing.
      #     Default: The input category's `validate_rows`, see RocketJob::Category::Input#upload_validates_rows?.
      #
      #   stream_mode: [:line | :array | :hash]
      #     Deprecated, and removed in Rocket Job 8: `validate_rows: true` replaces :hash, and for an input category
      #     without a format, its `format: :auto` reads a file into Hashes.
      #     :line
      #       Uploads the file a line (String) at a time for processing by workers.
      #     :array
      #       Parses each line from the file as an Array and uploads each array for processing by workers.
      #     :hash
      #       Parses each line from the file into a Hash and uploads each hash for processing by workers.
      #     See IOStreams::Stream#each.
      #
      #   category [Symbol|RocketJob::Category::Input]
      #     The category or the name of the category to access or download data from
      #     Default: None ( Uses the single default output collection for this job )
      #     Validates: This value must be one of those listed in #input_categories
      #
      # Example:
      #   # Load plain text records from a file
      #   job.upload('hello.csv')
      #
      # Example:
      #   # Load plain text records from a file, stripping all non-printable characters,
      #   # as well as any characters that cannot be converted to UTF-8
      #   path = IOStreams.path('hello.csv').encoding(cleaner: :printable, replace: '')
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
      #   path = IOStreams.path('myfile.ze').stream(:zip).stream(:enc).encoding('UTF-8')
      #   job.upload(path)
      #
      # Example: Supply custom options
      #   path = IOStreams.path('myfile.csv.enc').option(:enc, compress: false).encoding('UTF-8')
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
      #
      # Upload results from an Arel into RocketJob::SlicedJob.
      #
      # Params
      #   column_names
      #     When a block is not supplied, supply the names of the columns to be returned
      #     and uploaded into the job
      #     These columns are automatically added to the select list to reduce overhead
      #
      #   category [Symbol|RocketJob::Category::Input]
      #     The category or the name of the category to upload to.
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
      #   job.upload_arel(arel, columns: [:user_name, :zip_code])
      #
      # Notes:
      # * Only call from one thread at a time against a single instance of this job.
      # * The record_count for the job is set to the number of records returned by the arel.
      # * If an exception is raised while uploading data, the input collection is cleared out
      #   so that if a job is retried during an upload failure, data is not duplicated.

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
      # Example: Upload only the specified column(s)
      #   criteria = User.where(state: 'FL')
      #   job.record_count = job.upload_mongo_query(criteria, columns: [:zip_code])
      #
      # Notes:
      # * Only call from one thread at a time against a single instance of this job.
      # * The record_count for the job is set to the number of records returned by the monqo query.
      # * If an exception is raised while uploading data, the input collection is cleared out
      #   so that if a job is retried during an upload failure, data is not duplicated.

      # Upload sliced range of integer requests as arrays of start and end ids.
      #
      # Returns [Integer] the number of slices uploaded.
      #
      # Uploads one range per slice so that the response can return multiple records
      # for each slice processed
      #
      # Example
      #   job.input_category.slice_size = 100
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

      # Upload sliced range of integer requests as an arrays of start and end ids
      # starting with the last range first
      #
      # Returns [Integer] the number of slices uploaded.
      #
      # Uploads one range per slice so that the response can return multiple records
      # for each slice processed.
      # Useful for when the highest order integer values should be processed before
      # the lower integer value ranges. For example when processing every record
      # in a database based on the id column
      #
      # Example
      #   job.input_category.slice_size = 100
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

      def upload(object = nil, category: :main, file_name: nil, stream_mode: nil, validate_rows: nil, on_first: nil,
                 columns: nil, slice_batch_size: nil, **args, &block)
        input_collection = input(category)

        # A block uploads the records that it writes, unless it transforms the models or documents of a query, as it does
        # in Rocket Job 8, which passes each row of an Active Record relation to it as a Hash of its columns, see
        # Sliced::Input#upload_arel.
        if block && !rocketjob_query?(object)
          raise(ArgumentError, "Cannot supply both an object to upload, and a block.") if object

          rocketjob_check_no_validate_rows(validate_rows, "a block, whose records are uploaded as they are")
          if stream_mode || columns || slice_batch_size || args.size.positive?
            raise(ArgumentError,
                  "Unknown keyword arguments when uploading a block. Only accepts :category, :file_name, or :on_first")
          end

          rocketjob_warn_on_first if on_first
          category           = input_category(category)
          category.file_name = file_name if file_name

          # Extract the header line during the upload when applicable.
          extract_header = category.extract_header_callback(on_first)

          count             = input_collection.upload(on_first: extract_header, slice_batch_size: slice_batch_size, &block)
          self.record_count = (record_count || 0) + count
          return count
        end

        count =
          case object
          when Range
            rocketjob_check_no_validate_rows(validate_rows, "a Range, whose values are not the lines of a file")
            if file_name || stream_mode || on_first || args.size.positive?
              raise(ArgumentError,
                    "Unknown keyword arguments when uploading a Range. Only accepts :category, :columns, or :slice_batch_size")
            end

            first = object.first
            last  = object.last
            if first < last
              input_collection.upload_integer_range(first, last, slice_batch_size: slice_batch_size || 1_000)
            else
              input_collection.upload_integer_range_in_reverse_order(last, first, slice_batch_size: slice_batch_size || 1_000)
            end
          when Mongoid::Criteria
            rocketjob_check_no_validate_rows(validate_rows, "a Mongoid::Criteria, whose values are not the lines of a file")
            if file_name || stream_mode || on_first || args.size.positive?
              raise(ArgumentError,
                    "Unknown keyword arguments when uploading a Mongoid::Criteria. Only accepts :category, :columns, or :slice_batch_size")
            end

            input_collection.upload_mongo_query(object, columns: columns, slice_batch_size: slice_batch_size, &block)
          when defined?(ActiveRecord::Relation) ? ActiveRecord::Relation : false
            rocketjob_check_no_validate_rows(validate_rows, "an ActiveRecord::Relation, whose values are not the lines of a file")
            if file_name || stream_mode || on_first || args.size.positive?
              raise(ArgumentError,
                    "Unknown keyword arguments when uploading an ActiveRecord::Relation. Only accepts :category, :columns, or :slice_batch_size")
            end

            input_collection.upload_arel(object, columns: columns, slice_batch_size: slice_batch_size, &block)

          else
            raise(ArgumentError, "Unknown keyword argument :columns when uploading a file") if columns

            if stream_mode && !validate_rows.nil?
              raise(ArgumentError, "Supply either validate_rows:, or the deprecated stream_mode:, when uploading a file")
            end

            rocketjob_warn_deprecated_upload_options(args)
            rocketjob_warn_on_first if on_first
            category = input_category(category)
            category.warn_deprecated_stream_mode(stream_mode) if stream_mode
            category.check_upload(validate_rows)

            # The path sets the format of a category whose format is :auto, which decides whether the file has a
            # header row to extract during the upload.
            path           = category.upload_path(object, original_file_name: file_name)
            extract_header = category.extract_header_callback(on_first)

            input_collection.upload(on_first: extract_header, slice_batch_size: slice_batch_size) do |io|
              category.each_record(path, mode: stream_mode, validate_rows: validate_rows, **args) { |record| io << record }
            end

          end

        self.record_count = (record_count || 0) + count
        count
      end

      # @deprecated Removed in Rocket Job 8: call #upload with the relation instead.
      def upload_arel(arel, *column_names, category: :main, &)
        rocketjob_warn_removed_upload_method(
          "upload_arel", "the relation, with the columns to upload as columns:, such as " \
                         "upload(User.where(country_code: \"US\"), columns: %i[name zip_code])"
        )
        count             = input(category).upload_arel(arel, columns: column_names, &)
        self.record_count = (record_count || 0) + count
        count
      end

      # @deprecated Removed in Rocket Job 8: call #upload with the criteria instead.
      def upload_mongo_query(criteria, *column_names, category: :main, &)
        rocketjob_warn_removed_upload_method(
          "upload_mongo_query", "the criteria, with the fields to upload as columns:, such as " \
                                "upload(User.where(state: \"FL\"), columns: [:zip_code])"
        )
        count             = input(category).upload_mongo_query(criteria, columns: column_names, &)
        self.record_count = (record_count || 0) + count
        count
      end

      # @deprecated Removed in Rocket Job 8: call #upload with the range instead.
      def upload_integer_range(start_id, last_id, category: :main, slice_batch_size: 1_000)
        rocketjob_warn_removed_upload_method(
          "upload_integer_range", "the range, such as upload(1..1_000_000) for upload_integer_range(1, 1_000_000)"
        )
        count             = input(category).upload_integer_range(start_id, last_id, slice_batch_size: slice_batch_size)
        self.record_count = (record_count || 0) + count
        count
      end

      # @deprecated Removed in Rocket Job 8: call #upload with the range from its last id instead.
      def upload_integer_range_in_reverse_order(start_id, last_id, category: :main, slice_batch_size: 1_000)
        rocketjob_warn_removed_upload_method(
          "upload_integer_range_in_reverse_order",
          "the range from its last id, such as upload(1_000_000..1) for " \
          "upload_integer_range_in_reverse_order(1, 1_000_000)"
        )
        count             = input(category).upload_integer_range_in_reverse_order(start_id, last_id,
                                                                                  slice_batch_size: slice_batch_size)
        self.record_count = (record_count || 0) + count
        count
      end

      # Upload the supplied slice for processing by workers
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
      #   The caller should implement `:slice_size`, since the entire slice is saved as-is.
      #
      # Note:
      #   Not thread-safe. Only call from one thread at a time
      def upload_slice(slice, category: :main)
        input(category).insert(slice)
        count             = slice.size
        self.record_count = (record_count || 0) + count
        count
      end

      # The options that IOStreams reads a file with which describe its columns, and are deprecated, see
      # RocketJob::Category::Input#schema.
      DEPRECATED_UPLOAD_OPTIONS = %i[allowed_columns required_columns skip_unknown cleanse_header].freeze
      private_constant :DEPRECATED_UPLOAD_OPTIONS

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
      #   path = IOStreams.path('myfile.csv.zip').option(:zip, entry_file_name: 'myfile.csv')
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

        category           = output_category(category) unless category.is_a?(Category::Output)
        output_collection  = output(category)

        # Store the output file name in the category
        category.file_name = stream if !block && (stream.is_a?(String) || stream.is_a?(IOStreams::Path))

        header_line ||= category.render_header

        return output_collection.download(header_line: header_line, &block) if block

        raise(ArgumentError, "Missing mandatory `stream` or `category.file_name`") unless stream || category.file_name

        if output_collection.slice_class.binary_format
          binary_header_line = output_collection.slice_class.to_binary(header_line) if header_line

          # Don't overwrite supplied stream options if any
          stream = stream.is_a?(IOStreams::Stream) ? stream.dup : IOStreams.new(category.file_name)
          stream.remove_from_pipeline(output_collection.slice_class.binary_format)
          stream.writer(**args) do |io|
            # TODO: Binary formats should return the record count, instead of the slice count.
            output_collection.download(header_line: binary_header_line) { |record| io.write(record) }
          end
        else
          # TODO: Add category to named tags to aid problem determination
          # And RJ Download metric with duration
          IOStreams.new(stream || category.file_name).writer(:line, **args) do |io|
            output_collection.download(header_line: header_line) { |record| io << record }
          end
        end
      end

      private

      # Reports a deprecation warning, see RocketJob::Deprecation, at the line of the application that calls the named
      # upload method, which Rocket Job 8 removes, saying what to call #upload with instead.
      def rocketjob_warn_removed_upload_method(name, replacement)
        RocketJob::Deprecation.warn(
          "#{name} is deprecated, and removed in Rocket Job 8: call upload with #{replacement}, see " \
          "#{RocketJob::Deprecation::UPGRADE_GUIDE}"
        )
      end

      # Returns [true|false] whether the supplied object is a query that #upload uploads the records of, whose models
      # or documents a block can transform: a Mongoid::Criteria, or an ActiveRecord::Relation.
      def rocketjob_query?(object)
        object.is_a?(Mongoid::Criteria) || (defined?(ActiveRecord::Relation) && object.is_a?(ActiveRecord::Relation))
      end

      # Reports a deprecation warning, see RocketJob::Deprecation, at the line of the application that uploads with
      # `on_first`, which Rocket Job 8 removes: Rocket Job reads the header row itself, and a file without one, such as
      # JSON or fixed width, loses its first record, which a block that writes the other lines leaves out instead.
      def rocketjob_warn_on_first
        RocketJob::Deprecation.warn(
          "on_first: is deprecated, and removed in Rocket Job 8: Rocket Job reads the header row itself, which the " \
          "category's schema checks, and to leave out the first record of a file without a header row, upload with " \
          "a block that writes the other lines, see #{RocketJob::Deprecation::UPGRADE_GUIDE}"
        )
      end

      # Raises ArgumentError for the supplied `validate_rows:` of an upload of what is described, which has no lines to
      # validate, unless it is nil or false, which validates nothing.
      def rocketjob_check_no_validate_rows(validate_rows, what)
        return if [nil, false].include?(validate_rows)

        raise(ArgumentError, "validate_rows: #{validate_rows.inspect} cannot be supplied when uploading #{what}")
      end

      # Reports a deprecation warning, see RocketJob::Deprecation, at the line of the application that uploads a file
      # with options that describe the columns of the file, which the schema of the input category replaces.
      def rocketjob_warn_deprecated_upload_options(args)
        names = args.keys & DEPRECATED_UPLOAD_OPTIONS
        return if names.empty?

        RocketJob::Deprecation.warn(
          "#{names.collect { |name| "#{name}:" }.join(', ')} #{names.size == 1 ? 'is' : 'are'} deprecated, describe " \
          "the columns of the file with the schema: of the input category instead, see " \
          "#{RocketJob::Deprecation::UPGRADE_GUIDE}"
        )
      end
    end
  end
end

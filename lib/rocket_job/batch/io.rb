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
      #     Deprecated, and removed in Rocket Job 8, which detects the line endings of a file.
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
      #     which upload values rather than the lines of a file, for which false is accepted, since it validates
      #     nothing. Also raises when supplied, true or false, with a `stream_mode:` other than nil or false, which
      #     decides alone whether the lines are validated.
      #     Default: The input category's `validate_rows`, see RocketJob::Category::Input#upload_validates_rows?.
      #
      #   stream_mode: [:line | :array | :hash]
      #     Deprecated, and removed in Rocket Job 8, which raises ArgumentError whenever it is supplied, also as nil, so
      #     it reports a deprecation warning then too: `validate_rows: true` replaces :hash, and for an input category
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
      # * The number of records uploaded is added to the record_count of the job.
      # * If an exception is raised while uploading data, the records that this upload stored are removed, so that
      #   if the job is retried, its data is not duplicated. The records of earlier uploads are kept.
      # * The text of the file/stream is read as UTF-8 before being persisted, since MongoDB only stores UTF-8 strings.
      #   Text that is not valid UTF-8 raises IOStreams::Errors::InvalidEncoding, naming its line, unless an encoding
      #   is set on the path, such as `IOStreams.path("names.txt").encoding("ISO-8859-1")`, which reads it instead.
      #   An input category with a format but no schema ignores an encoding set on the path, and removes
      #   non-printable characters, and every character that is not ASCII, instead.
      # * When zip format, the Zip file/stream must contain only one file, the first file found will be
      #   loaded into the job
      # * If an io stream is supplied, it is read until it returns nil.
      # * Only use this method for UTF-8 data, for binary data use #input_slice or #input_records.
      # * CSV parsing is slow, so it is usually left for the workers to do.
      #
      # Upload the records of a query or a range of integers, which replaces upload_arel, upload_mongo_query,
      # upload_integer_range and upload_integer_range_in_reverse_order, that Rocket Job 8 removes:
      #
      # Example: Upload the id of each user that an Active Record relation returns
      #   job.upload(User.where(country_code: "US"))
      #
      # Example: Upload the user_name and zip_code of each user, as an Array, see `columns:`
      #   job.upload(User.where(country_code: "US"), columns: %i[user_name zip_code])
      #
      # Example: Upload what a block computes for each user, by writing the records in the block
      #   job.upload do |records|
      #     User.where(country_code: "US").find_each do |user|
      #       records << user.email.downcase
      #     end
      #   end
      #
      # Example: Upload the zip_code of each document that a Mongoid query returns
      #   job.upload(User.where(state: "FL"), columns: [:zip_code])
      #
      # Example: Upload the ids 200 to 421 as one `[first_id, last_id]` range per slice, of `slice_size` ids each
      #   job.input_category.slice_size = 100
      #   job.upload(200..421)
      #
      #   # Uploads the slices:
      #   [200, 299]
      #   [300, 399]
      #   [400, 421]
      #
      # Example: Upload the same ids from the last one, such as to process the highest ids first
      #   job.input_category.slice_size = 100
      #   job.upload(421..200)
      #
      #   # Uploads the slices:
      #   [322, 421]
      #   [222, 321]
      #   [200, 221]
      #
      # Notes for a query or a range:
      # * `columns:` is only for a query: the columns, or fields, to upload. One column uploads its value, and several
      #   an Array of their values. Default: the id.
      # * The rows of an Active Record relation are read with `find_each`, selecting the columns and the id, and each
      #   column is uploaded as the reader of the model returns it. See Sliced::Input::QueryDeprecation for what
      #   Rocket Job 8 uploads differently.
      # * The documents of a Mongoid query are read with the MongoDB driver, without building a model for each one.
      # * A block passed with a query is deprecated, since Rocket Job 8 raises ArgumentError for it: it receives each
      #   model of a relation, or each document of a Mongoid query as a Hash, and returns the record to upload. Supplying
      #   `columns:` with it raises ArgumentError. Write the records in the block of upload instead, as above.
      # * The number that is returned and added to `record_count` is the number of records uploaded, which for a range
      #   is the number of `[first_id, last_id]` ranges, one per slice.
      # * If an exception is raised while uploading data, the records that this upload stored are removed, so that
      #   if the job is retried, its data is not duplicated. The records of earlier uploads are kept.
      def upload(object = nil, category: :main, file_name: nil, stream_mode: UPLOAD_OPTION_OMITTED, validate_rows: nil,
                 on_first: UPLOAD_OPTION_OMITTED, columns: nil, slice_batch_size: nil, **args, &block)
        # Rocket Job 8 raises for on_first and stream_mode whenever they are passed, also as nil, whatever is uploaded.
        if on_first.equal?(UPLOAD_OPTION_OMITTED)
          on_first = nil
        else
          rocketjob_warn_on_first
        end
        input_collection = input(category)
        if stream_mode.equal?(UPLOAD_OPTION_OMITTED)
          stream_mode = nil
        else
          rocketjob_check_stream_mode(stream_mode, category)
        end

        # A block uploads the records that it writes, unless it is passed with a query, whose models or documents it
        # transforms, as upload_arel and upload_mongo_query did. Rocket Job 8 raises for a block passed with a query, see
        # Sliced::Input::QueryDeprecation.
        if block && !rocketjob_query?(object)
          raise(ArgumentError, "Cannot supply both an object to upload, and a block.") if object

          rocketjob_check_no_validate_rows(validate_rows, "a block, whose records are uploaded as they are")
          if stream_mode || columns || slice_batch_size || args.size.positive?
            raise(ArgumentError,
                  "Unknown keyword arguments when uploading a block. Only accepts :category, :file_name, or :on_first")
          end

          category           = input_category(category)
          category.file_name = file_name if file_name

          # Extract the header line during the upload when applicable.
          count = category.upload_header(on_first, uploaded: input_collection.exists?) do |extract_header|
            input_collection.upload(on_first: extract_header, slice_batch_size: slice_batch_size, &block)
          end
          self.record_count = (record_count || 0) + count
          return count
        end

        # The block passed with a query returns the record to upload in place of the columns.
        raise(ArgumentError, "Cannot supply both :columns and a block when uploading a query.") if block && columns

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
            category = input_category(category)
            category.check_upload(validate_rows)

            # The path sets the format of a category whose format is :auto, which decides whether the file has a
            # header row to extract during the upload.
            path = category.upload_path(object, original_file_name: file_name)
            category.upload_header(on_first, uploaded: input_collection.exists?) do |extract_header|
              input_collection.upload(on_first: extract_header, slice_batch_size: slice_batch_size) do |io|
                category.each_record(path, mode: stream_mode, validate_rows: validate_rows, **args) { |record| io << record }
              end
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

      # The default of the deprecated `on_first:` and `stream_mode:` options of #upload, so that passing either, even as
      # nil, can be told from leaving it out, see #rocketjob_warn_on_first and #rocketjob_check_stream_mode. Named for
      # upload, since a batch job includes this module, where a constant named OMITTED would hide one of the
      # application's.
      UPLOAD_OPTION_OMITTED = Object.new.freeze
      private_constant :UPLOAD_OPTION_OMITTED

      # The options that IOStreams reads the lines of a file with, which are deprecated, since Rocket Job 8 reads the
      # lines itself: IOStreams detects the line endings of a file, and the format of the input category reads a quoted
      # value that holds line breaks. Each holds what its deprecation warning says replaces it, see
      # #rocketjob_warn_deprecated_upload_options.
      DEPRECATED_LINE_UPLOAD_OPTIONS = {
        delimiter:       "line endings are detected, and records separated by something else are written in the " \
                         'block of upload, such as with IOStreams.path(file_name).each(:line, delimiter: "|")',
        buffer_size:     "the size of the buffer that it reads with is its own",
        embedded_within: "the input category's format reads a quoted value with line breaks, while 7.2 reads one in " \
                         "the format of the path that is uploaded, such as a file name ending in .csv, or " \
                         "IOStreams.stream(io).format(:csv)"
      }.freeze
      private_constant :DEPRECATED_LINE_UPLOAD_OPTIONS

      # Returns [Array<Symbol>] the options of #upload that are deprecated: the column options that the input category
      # reads a file with, see RocketJob::Category::Input::DEPRECATED_UPLOAD_OPTIONS, the options that read the lines
      # of a file, see DEPRECATED_LINE_UPLOAD_OPTIONS, `on_first`, see #rocketjob_warn_on_first, and `stream_mode`, see
      # #rocketjob_check_stream_mode.
      def self.deprecated_upload_options
        [*RocketJob::Category::Input::DEPRECATED_UPLOAD_OPTIONS, *DEPRECATED_LINE_UPLOAD_OPTIONS.keys, :on_first, :stream_mode]
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
          "#{RocketJob::Deprecation::UPGRADE_GUIDE_V72}"
        )
      end

      # Returns [true|false] whether the supplied object is a query that #upload uploads the records of, whose models
      # or documents a block can transform: a Mongoid::Criteria, or an ActiveRecord::Relation.
      def rocketjob_query?(object)
        object.is_a?(Mongoid::Criteria) || (defined?(ActiveRecord::Relation) && object.is_a?(ActiveRecord::Relation))
      end

      # Reports a deprecation warning, see RocketJob::Deprecation, at the line of the application that uploads with
      # `on_first`, also as nil, whatever it uploads, since Rocket Job 8 removes it, and raises ArgumentError for it: Rocket
      # Job reads the header row itself, and a file without one, such as JSON or fixed width, loses its first record,
      # which a block that writes the other lines leaves out instead.
      def rocketjob_warn_on_first
        RocketJob::Deprecation.warn(
          "on_first: is deprecated, and removed in Rocket Job 8, which raises for it, also when nil: Rocket Job reads " \
          "the header row itself, which the category's schema checks, and to leave out the first record of a file " \
          "without a header row, upload with a block that writes the other lines, see " \
          "#{RocketJob::Deprecation::UPGRADE_GUIDE_V72}"
        )
      end

      # Reports a deprecation warning, see RocketJob::Category::Input#warn_deprecated_stream_mode, for the supplied
      # `stream_mode:` of an upload into the supplied category, also when nil, whatever is uploaded, since Rocket Job 8
      # removes it, and raises ArgumentError for it. Raises ArgumentError for a stream_mode other than :line, :array or
      # :hash, before warning for it, as 7.1 did without a schema. With a schema 7.1 read such a stream_mode as :hash.
      def rocketjob_check_stream_mode(stream_mode, category)
        if stream_mode && !%w[line array hash].include?(stream_mode.to_s)
          raise(ArgumentError, "Invalid stream_mode: #{stream_mode.inspect}, which can only be :line, :array or :hash")
        end

        input_category(category).warn_deprecated_stream_mode(stream_mode)
      end

      # Raises ArgumentError for the supplied `validate_rows:` of an upload of what is described, which has no lines to
      # validate, unless it is nil or false, which validates nothing.
      def rocketjob_check_no_validate_rows(validate_rows, what)
        return if [nil, false].include?(validate_rows)

        raise(ArgumentError, "validate_rows: #{validate_rows.inspect} cannot be supplied when uploading #{what}")
      end

      # Reports a deprecation warning, see RocketJob::Deprecation, at the line of the application that uploads a file
      # with options that describe the columns of the file, which the schema of the input category replaces, see
      # RocketJob::Category::Input::DEPRECATED_UPLOAD_OPTIONS, and another
      # for options that read its lines, which Rocket Job 8 removes, saying what replaces each of those that is passed,
      # see DEPRECATED_LINE_UPLOAD_OPTIONS: IOStreams detects the line endings of a file, \r\n or \n, the size of the
      # buffer that it reads with is its own, and the format of the input category, such as CSV, reads a quoted value
      # that holds line breaks. 7.2 reads such a value in the format of the path that is uploaded, which has one when
      # its file name gives it, or when one is set on the path, see Category::Input#upload_path.
      def rocketjob_warn_deprecated_upload_options(args)
        rocketjob_warn_upload_options(
          args.keys & RocketJob::Category::Input::DEPRECATED_UPLOAD_OPTIONS,
          "describe the columns of the file with the schema: of the input category instead, see " \
          "#{RocketJob::Deprecation::UPGRADE_GUIDE}"
        )
        names = args.keys & DEPRECATED_LINE_UPLOAD_OPTIONS.keys
        rocketjob_warn_upload_options(
          names,
          "and removed in Rocket Job 8, which reads the lines of a file itself: " \
          "#{DEPRECATED_LINE_UPLOAD_OPTIONS.values_at(*names).join('; ')}, see #{RocketJob::Deprecation::UPGRADE_GUIDE_V72}"
        )
      end

      # Reports a deprecation warning, see RocketJob::Deprecation, naming the supplied deprecated options of an upload
      # that were passed, if any, followed by the supplied reason.
      def rocketjob_warn_upload_options(names, reason)
        return if names.empty?

        RocketJob::Deprecation.warn(
          "#{names.collect { |name| "#{name}:" }.join(', ')} #{names.size == 1 ? 'is' : 'are'} deprecated, #{reason}"
        )
      end
    end
  end
end

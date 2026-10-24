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
      #     Default: :main
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
      #     Default: :main
      #     Validates: This value must be one of those listed in #output_categories
      def output(category = :main)
        category = output_category(category)

        (@outputs ||= {})[category.name] ||= category.data_store(self)
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
      #   validate_rows: [true | false]
      #     Whether to parse each row of the file in the input category's format, such as CSV, as it is uploaded, so
      #     that a file with a row that cannot be read, or with a value that is not valid for its field, is rejected
      #     before any of it is processed. The slices still hold the lines, which the workers parse.
      #     Raises ArgumentError when true for an input category without a format, whose records are uploaded as they
      #     are, or for a query or a range, which upload values rather than the rows of a file, so that the category's
      #     `validate_rows` does not apply to them either.
      #     Default: The input category's `validate_rows`, see RocketJob::Category::Input#upload_validates_rows?.
      #
      #   `stream_mode:` was removed in Rocket Job v8, and raises ArgumentError: `validate_rows: true` replaces
      #   `stream_mode: :hash`, and for a category without a format, its `format: :auto` reads a file into Hashes.
      #
      #   category [Symbol|RocketJob::Category::Input]
      #     The category or the name of the category to upload the data into
      #     Default: :main
      #     Validates: This value must be one of those listed in #input_categories
      #
      # Example:
      #   # Load plain text records from a file
      #   job.upload('hello.csv')
      #
      # Example:
      #   # Load plain text records from a file, stripping all non-printable characters,
      #   # as well as any characters that are not valid UTF-8
      #   path = IOStreams.path('hello.txt').encoding(cleaner: :printable, replace: '')
      #   job.upload(path)
      #
      # Example:
      #   # Load a file that is not UTF-8, converting its records to UTF-8.
      #   path = IOStreams.path('hello.csv').encoding('Windows-1252:UTF-8')
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
      #   path = IOStreams.path('myfile.ze').stream(:zip).stream(:enc)
      #   job.upload(path)
      #
      # Example: Supply custom options
      #   path = IOStreams.path('myfile.csv.enc').option(:enc, compress: false)
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
      # The block of an upload into an input category with a format, such as CSV, writes the lines of a file, its header
      # row first, which are uploaded as a file is, and takes `validate_rows:` too. Each line is read as UTF-8, converted
      # from its encoding, and each character that is not valid in it is removed, replaced or raises, as the input
      # category's `invalid_characters` says. Its non-printable characters are removed, or replaced with spaces in a
      # fixed width format, as those of a file are, see RocketJob::Category::Input#write_slices.
      #
      # Notes:
      # * Only call from one thread at a time against a single instance of this job.
      # * The number of records uploaded is added to the record_count of the job.
      # * If an exception is raised while uploading data, the records that this upload stored are removed, so that
      #   if the job is retried, its data is not duplicated. The records of earlier uploads are kept.
      # * Files are read as UTF-8 text, since MongoDB only stores UTF-8 strings. A UTF-8 byte order mark at
      #   the start of the file is removed. Data that is not valid UTF-8 raises
      #   Encoding::UndefinedConversionError and nothing is uploaded, unless the file's encoding is set, either
      #   as the input category's `encoding`, or on the path with `encoding(...)`, which takes its place, or
      #   `replace:` is supplied to remove invalid characters.
      #   Tabular formats, such as CSV, remove non-printable and invalid characters by default.
      # * Fixed width files are read as ASCII, and raise for any other character unless the file's encoding is
      #   set, such as the category's `encoding: "ISO-8859-1"`. Non-printable characters are replaced with spaces.
      # * When zip format, the Zip file/stream must contain only one file, the first file found will be
      #   loaded into the job
      # * If an io stream is supplied, it is read until it returns nil.
      # * Binary data cannot be uploaded as records, since they are stored as UTF-8 strings.
      # * CSV parsing is slow, so it is usually left for the workers to do.
      #
      # Upload the records of a query or a range of integers, as the removed `upload_arel`, `upload_mongo_query`,
      # `upload_integer_range` and `upload_integer_range_in_reverse_order` did:
      #
      # Example: Upload the id of each user that an Active Record relation returns
      #   job.upload(User.where(country_code: "US"))
      #
      # Example: Upload the user_name and zip_code of each user, as an Array, see `columns:`
      #   job.upload(User.where(country_code: "US"), columns: %i[user_name zip_code])
      #
      # Example: Upload the id of each user in batches of 10,000, for a database that cannot stream a query, such as
      #   MySQL with trilogy, selecting the columns before `in_batches`
      #   job.upload(User.where(country_code: "US").select(:id).in_batches(of: 10_000))
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
      # Example: Upload the ids 200 to 421 as one `[first_id, last_id]` range per slice, of `slice_size` ids each,
      #   starting with the last range when the range is descending, such as `421..200`
      #   job.upload(200..421)
      #
      # Notes for a query or a range:
      # * `columns:` is only for a query: the columns, or fields, to upload. Default: the id. The batches of a relation
      #   upload the columns that the relation selects instead, and raise ArgumentError for `columns:`, and for a
      #   relation that selects no columns.
      # * IOStreams reads an Active Record relation as one query that the database streams, without building a model
      #   for each row, so the rows are uploaded in the order of the relation and within its limit, and each column is
      #   read as `pluck` reads it. See `IOStreams.stream`.
      # * IOStreams reads a relation on a connection of its own, checked out of the pool of the model, so that:
      #   * The pool needs a connection free besides the one of the caller, for each thread that uploads at the same
      #     time, otherwise `upload` raises `ActiveRecord::ConnectionTimeoutError` once the pool's `checkout_timeout`
      #     passes, such as within a transaction, or in a job that includes `RocketJob::Plugins::Transaction`.
      #   * Only the rows that were committed are uploaded: the rows that an open transaction of the caller wrote are
      #     not, without an error, so upload them once that transaction commits.
      #   * The query stays open until every row is uploaded, holding one snapshot of the database for that long. For a
      #     very large upload, upload the batches of the relation instead, which run a short query for each batch.
      #   The batches of a relation are read on the connection of the caller instead.
      # * IOStreams reads a relation, and its batches, with Active Record 7.2 or later, and raises ArgumentError for an
      #   earlier version.
      # * The number that is returned and added to `record_count` is the number of records uploaded, which for a
      #   range is the number of integers in it, although each slice holds one `[first_id, last_id]` record.
      # * If an exception is raised while uploading, the records that this upload stored are removed, so that if the
      #   job is retried, its data is not duplicated.
      def upload(object = nil, category: :main, file_name: nil, validate_rows: nil, columns: nil, slice_batch_size: nil,
                 **args, &block)
        rocketjob_check_on_first(args)
        rocketjob_check_stream_mode(args)
        input_collection = input(category)

        if block
          raise(ArgumentError, "Cannot supply both an object to upload, and a block.") if object
          if columns || slice_batch_size || args.size.positive?
            raise(ArgumentError,
                  "Unknown keyword arguments when uploading a block. Only accepts :category, :file_name, or " \
                  ":validate_rows")
          end

          category = input_category(category)
          category.check_upload(validate_rows)

          # Restores the file name that the upload sets when it raises, see Category::Input#uploading.
          count =
            category.uploading do
              category.file_name = file_name if file_name
              if category.slices?
                # The block writes the lines of a file, which are read in slices, as the lines of a file are.
                input_collection.upload(upload_id: rocketjob_upload_id) do |writer|
                  category.write_slices(writer, validate_rows: validate_rows, &block)
                end
              else
                input_collection.upload(upload_id: rocketjob_upload_id, &block)
              end
            end
          return rocketjob_add_record_count(count)
        end

        # The options that only apply to a file, which a range or a query rejects: `validate_rows: false` asks for
        # nothing that it does not do, since it uploads values, rather than the rows of a file.
        file_options = args.merge(file_name: file_name, validate_rows: validate_rows || nil).compact
        count =
          case object
          when Range
            rocketjob_check_upload("a Range", ":category, or :slice_batch_size", category, file_options)
            rocketjob_upload_integer_range(input_collection, object, slice_batch_size || 1_000, rocketjob_upload_id)
          when Mongoid::Criteria
            rocketjob_check_upload("a Mongoid::Criteria", ":category, :columns, or :slice_batch_size",
                                   category, file_options)
            input_collection.upload_mongo_query(object, columns: columns, slice_batch_size: slice_batch_size,
                                                        upload_id: rocketjob_upload_id)
          when ->(query) { rocketjob_active_record_query?(query) }
            if object.is_a?(ActiveRecord::Relation)
              rocketjob_check_upload("an ActiveRecord::Relation", ":category, :columns, or :slice_batch_size",
                                     category, file_options)
            else
              rocketjob_check_upload("the batches of an ActiveRecord::Relation", ":category, or :slice_batch_size",
                                     category, file_options)
            end
            input_collection.upload_arel(object, columns: columns, slice_batch_size: slice_batch_size,
                                                 upload_id: rocketjob_upload_id)
          else
            raise(ArgumentError, "Unknown keyword argument :columns when uploading a file") if columns

            rocketjob_check_upload_file_options(args)
            category = input_category(category)
            category.check_upload(validate_rows)

            # Restores the fields that the upload sets when it raises, such as the format that :auto is replaced with.
            category.uploading do
              # Sets the format first when it is :auto, since the format determines whether there is a header line.
              path = category.upload_path(object, original_file_name: file_name)

              if category.slices?
                rocketjob_upload_slices(input_collection, category, path,
                                        validate_rows:    validate_rows,
                                        slice_batch_size: slice_batch_size)
              else
                input_collection.upload(slice_batch_size: slice_batch_size, upload_id: rocketjob_upload_id) do |io|
                  category.each_record(path) { |record| io << record }
                end
              end
            end
          end
        rocketjob_add_record_count(count)
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
        rocketjob_add_record_count(slice.size)
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

        if output_collection.binary_format
          # The slices of a binary format already hold their text in the category's encoding, see
          # Category::Output#text_encoding, so the header line is written in it too.
          binary_header_line = output_collection.binary_header(header_line) if header_line

          # Don't overwrite supplied stream options if any
          stream = stream.is_a?(IOStreams::Stream) ? stream.dup : IOStreams.new(category.file_name)
          if stream.setting(:encode)
            raise(ArgumentError,
                  "Set the encoding of output written by the #{category.serializer.inspect} serializer as the output " \
                  "category's `encoding`, not on the download path, since its slices are already written in it.")
          end

          stream.remove_from_pipeline(output_collection.binary_format)
          stream.writer(**args) do |io|
            # TODO: Binary formats should return the record count, instead of the slice count.
            output_collection.download(header_line: binary_header_line) { |record| io.write(record) }
          end
        else
          # TODO: Add category to named tags to aid problem determination
          # And RJ Download metric with duration
          category.download_path(stream).writer(:line, **args) do |io|
            output_collection.download(header_line: header_line) { |record| io << record }
          end
        end
      end

      private

      # The upload id of the slices that the before_batch callbacks upload, see Sliced::Slice#upload_id.
      BEFORE_BATCH_UPLOAD = "before_batch".freeze
      private_constant :BEFORE_BATCH_UPLOAD

      # The options of #upload that describe the columns of the file, which Rocket Job v8 removed, since the schema of the
      # input category replaces them, see #rocketjob_check_upload_file_options.
      REMOVED_UPLOAD_OPTION_NAMES = %i[allowed_columns required_columns skip_unknown cleanse_header].freeze
      private_constant :REMOVED_UPLOAD_OPTION_NAMES

      # The options of #upload that read the lines of a file, which Rocket Job v8 removed, since it reads the lines
      # itself: IOStreams detects their line endings, and the format of the input category reads a quoted value that
      # holds line breaks, see #rocketjob_check_upload_file_options.
      REMOVED_LINE_OPTION_NAMES = %i[delimiter buffer_size embedded_within].freeze
      private_constant :REMOVED_LINE_OPTION_NAMES

      # Where the upgrade guide says what replaces the options of #upload that read the lines of a file.
      LINE_OPTIONS_GUIDE = "https://rocketjob.reidmorrison.com/upgrading.html#line-options-of-upload".freeze
      private_constant :LINE_OPTIONS_GUIDE

      # Where the upgrade guide says what replaces `on_first`, which Rocket Job v8 removed.
      ON_FIRST_GUIDE = "https://rocketjob.reidmorrison.com/upgrading.html#replace-on_first".freeze
      private_constant :ON_FIRST_GUIDE

      # Returns [Hash] the `record_count` and the upload state of each input category, see
      # Category::Input#upload_state, which the before_batch callbacks start with, see #before_batch_state.
      def rocketjob_before_batch_state
        {
          "record_count"     => record_count,
          "input_categories" => input_categories.to_h { |category| [category.name.to_s, category.upload_state] }
        }
      end

      # Removes the slices that the before_batch callbacks uploaded, and restores the `record_count` and the upload
      # state of each input category that they started with, see #before_batch_state, so that they can run again
      # without duplicating their input, such as when the job is retried.
      def rocketjob_undo_before_batch
        state = before_batch_state
        return unless state

        self.record_count = state["record_count"]
        input_categories.each do |category|
          input(category).delete_upload(BEFORE_BATCH_UPLOAD)
          category_state = state.dig("input_categories", category.name.to_s)
          category.restore_upload_state(category_state) if category_state
        end
        self.before_batch_state = nil
      end

      # Returns [String] the upload id of the slices of an upload while the before_batch callbacks run, so that they
      # can be removed when the job is retried, see #rocketjob_undo_before_batch, otherwise nil.
      def rocketjob_upload_id
        BEFORE_BATCH_UPLOAD if before_batch_state
      end

      # Returns [Integer] the supplied number of records uploaded, after adding it to `record_count`.
      def rocketjob_add_record_count(count)
        self.record_count = (record_count || 0) + count
        count
      end

      # Returns [true|false] whether the supplied object is an Active Record query that #upload uploads the rows of: a
      # relation, or the batches of one that `relation.in_batches` returns without a block.
      def rocketjob_active_record_query?(object)
        return false unless defined?(ActiveRecord::Relation)

        object.is_a?(ActiveRecord::Relation) || object.is_a?(ActiveRecord::Batches::BatchEnumerator)
      end

      # Raises ArgumentError for `on_first`, which Rocket Job v8 removed, also when nil, for any object uploaded, saying
      # what replaces it: Rocket Job reads the header row itself, and a file without one, such as JSON or fixed width,
      # lost its first record, which a block that writes the other lines leaves out instead.
      def rocketjob_check_on_first(args)
        return unless args.key?(:on_first)

        raise(ArgumentError,
              "on_first: was removed in Rocket Job v8: Rocket Job reads the header row itself, which the category's " \
              "schema checks, and to leave out the first record of a file without a header row, upload with a block " \
              "that writes the other lines, see #{ON_FIRST_GUIDE}")
      end

      # Raises ArgumentError for `stream_mode`, which Rocket Job v8 removed, also when nil, for any object uploaded, saying
      # what replaces it: `validate_rows: true` checks each row of a file in the category's format as it is uploaded,
      # which `stream_mode: :hash` did, and a category without a format reads a file into Hashes with `format: :auto`.
      def rocketjob_check_stream_mode(args)
        return unless args.key?(:stream_mode)

        raise(ArgumentError,
              "stream_mode: was removed in Rocket Job v8: use validate_rows: true in place of stream_mode: :hash to " \
              "parse each row of a file in the input category's format when it is uploaded, and to read a file into " \
              "Hashes, set the format of the input category, such as to :auto, see #{RocketJob::Category::Input::VALIDATE_ROWS_GUIDE}")
      end

      # Raises ArgumentError for any option of #upload of a file that is not named, since IOStreams reads the file as the
      # input category says: those that describe the columns of the file, see REMOVED_UPLOAD_OPTION_NAMES, naming the
      # schema that replaces them, and those that read its lines, see REMOVED_LINE_OPTION_NAMES, which Rocket Job v8
      # removed, also when nil, and any other.
      def rocketjob_check_upload_file_options(args)
        names = args.keys & REMOVED_UPLOAD_OPTION_NAMES
        raise(ArgumentError, Category::Input.removed_options_message(names.collect { |name| "#{name}:" })) if names.any?

        names = args.keys & REMOVED_LINE_OPTION_NAMES
        if names.any?
          raise(ArgumentError, "#{names.collect { |name| "#{name}:" }.join(', ')} #{names.size == 1 ? 'was' : 'were'} " \
                               "removed in Rocket Job v8, which reads the lines of a file itself: line endings are " \
                               "detected, and the input category's format reads a quoted value with line breaks, see " \
                               "#{LINE_OPTIONS_GUIDE}")
        end
        return if args.empty?

        raise(ArgumentError, "Unknown keyword #{args.size == 1 ? 'argument' : 'arguments'} " \
                             "#{args.keys.map(&:inspect).join(', ')} when uploading a file")
      end

      # Uploads the file that the supplied path reads into the supplied input category, which has a format, in the slices
      # of its rows that IOStreams writes to the input, each of which carries the header row of the file, see
      # Category::Input#copy_slices.
      #
      # Returns [Integer] the number of records uploaded.
      def rocketjob_upload_slices(input_collection, category, path, validate_rows:, slice_batch_size:)
        input_collection.upload(slice_batch_size: slice_batch_size, upload_id: rocketjob_upload_id) do |writer|
          category.copy_slices(path, writer, validate_rows: validate_rows)
        end
      end

      # Uploads the integers of the supplied range as one `[first_id, last_id]` record per slice, starting with the last
      # slice when the range is descending, such as `421..200`. An end that the range excludes, such as `200...421`, is
      # not uploaded.
      #
      # Returns [Integer] the number of integers uploaded, rather than of records, since each record is a range of
      # `slice_size` integers, see #percent_complete.
      def rocketjob_upload_integer_range(input_collection, range, slice_batch_size, upload_id)
        first = range.begin
        last  = range.end
        unless first.is_a?(Integer) && last.is_a?(Integer)
          raise(ArgumentError, "Only a Range with an Integer at each end can be uploaded, not #{range.inspect}")
        end
        return 0 if range.exclude_end? && first == last

        last += first < last ? -1 : 1 if range.exclude_end?
        if first < last
          input_collection.upload_integer_range(first, last, slice_batch_size: slice_batch_size, upload_id: upload_id)
        else
          input_collection.upload_integer_range_in_reverse_order(last, first, slice_batch_size: slice_batch_size,
                                                                              upload_id:        upload_id)
        end
        (last - first).abs + 1
      end

      # Raises ArgumentError when an option that only applies to a file is supplied to upload the supplied kind of
      # object, a range or a query, naming the options that it accepts, or when the input category of the supplied name
      # cannot parse its records, see RocketJob::Category::Input#check_record_upload.
      def rocketjob_check_upload(kind, accepts, category, file_options)
        unless file_options.empty?
          raise(ArgumentError, "Unknown keyword arguments when uploading #{kind}. Only accepts #{accepts}")
        end

        input_category(category).check_record_upload(kind)
      end
    end
  end
end

module RocketJob
  module Category
    # Define the layout for each category of input or output data
    class Input
      include SemanticLogger::Loggable
      include Plugins::Document
      include Category::Base

      embedded_in :job, class_name: "RocketJob::Job", inverse_of: :input_categories

      # The fields that an upload sets, see #upload_state.
      UPLOAD_FIELDS = %w[file_name format].freeze
      private_constant :UPLOAD_FIELDS

      # Where the upgrade guide says what replaces the `mode` of a category, and the `stream_mode:` of an upload, which
      # Rocket Job v8 removed, see #validate_rows.
      VALIDATE_ROWS_GUIDE = "https://rocketjob.reidmorrison.com/upgrading.html#replace-the-hash-mode-with-validate_rows".freeze

      # The values of the `mode` that Rocket Job 7 saved, which v8 removed, that are read as the `validate_rows` that
      # replaces it, see #convert_saved_mode: "hash", and "line", the default, which had no effect.
      CONVERTED_MODES = %w[hash line].freeze
      private_constant :CONVERTED_MODES

      # Replaces each non-printable character, other than line endings, with a space.
      FIXED_WIDTH_CLEANER = ->(data, _replace) { data.gsub(/[^[:print:]\r\n]/, " ") }
      private_constant :FIXED_WIDTH_CLEANER

      # Slice size for this input collection
      field :slice_size, type: Integer, default: 100
      validates_presence_of :slice_size

      # The header row of a file that Rocket Job 7 uploaded in a tabular format without a schema, such as CSV, with each
      # column cleansed, such as `first_name` for the column `First Name`, which the workers read each of its lines by,
      # see #parse_record. Rocket Job v8 does not set them, since each slice of a file holds its header row instead, see
      # #copy_slices.
      #
      # Rocket Job v8 removed setting them for a file without a header row, see .removed_option_names, so an upload
      # raises while they are set, see #check_columns_not_set. Describe the columns of such a file with a schema with
      # `"header" => false` instead.
      field :columns, type: Array

      # Whether `#upload` parses each row of a file in this category's format, see #format, as it uploads it, so that a
      # file with a row that cannot be read, or with a value that is not valid for its field, see #schema, is rejected
      # before any of it is processed. The slices still hold the lines, which the workers parse, see #copy_slices.
      #
      # Use it when the entire file must be validated before processing is started, and upload time is not important,
      # since the rows are parsed one after another while the file is uploaded.
      #
      # Needs a format: a category without one uploads each record as it is, see #each_record. Only a file, and the lines
      # that the block of an upload writes, are validated: a query or a range uploads values, rather than the rows of a
      # file, see RocketJob::Batch::IO#upload.
      #
      # Replaces the `mode` of Rocket Job 7, which v8 removed, see .removed_option_names: a category that Rocket Job 7
      # saved with `mode: :hash` and a format is read with `validate_rows: true`, see #convert_saved_mode, as are the
      # properties of such a category that a Dirmon entry or an UploadFileJob saved, see #convert_saved_properties.
      #
      # Default: nil, so that a category saved with `validate_rows: false` and `mode: :hash` is read with false.
      field :validate_rows, type: ::Mongoid::Boolean
      validate :validate_rows_has_format

      # Reads the `mode` of a category that Rocket Job 7 saved, which v8 removed, see .removed_option_names.
      after_initialize :convert_saved_mode

      # What `#upload` does with each character of a file that is not valid in the file's encoding, see #encoding, or of
      # a line that the block of an upload writes in this category's format that is not valid in the line's encoding,
      # see #write_slices:
      #   :remove
      #     Removes it.
      #   :replace
      #     Replaces it with U+FFFD, the Unicode replacement character, so that it can be seen in the record.
      #   :raise
      #     Raises IOStreams::Errors::InvalidEncoding, which names the byte offset and line of the first one, and
      #     uploads nothing.
      #   nil
      #     The format's own: tabular formats, such as CSV, remove it, while fixed width files and lines raise.
      #
      # A `replace:` set on the path supplied to `#upload` is used instead. The records that the block of an upload
      # writes into a category without a format, or in a format whose rows are not lines, such as :hash, are uploaded as
      # they are, see Sliced::Writer::Input, so text in them that is not valid UTF-8 raises.
      # Default: nil
      field :invalid_characters, type: ::Mongoid::StringifiedSymbol
      validates_inclusion_of :invalid_characters, in: [nil, :remove, :replace, :raise]

      validates_inclusion_of :serializer, in: %i[none compress encrypt]

      # Setting the columns builds the tabular again when it is next used, see #tabular.
      def columns=(value)
        @tabular = nil
        super
      end

      # Returns [Array<String>] the names of the options of an input category that Rocket Job v8 removed, see
      # Category::Base.removed_option_names: its column options, `allowed_columns`, `required_columns`, `skip_unknown`
      # and `header_cleanser`, the `columns` of a file without a header row, which an application can no longer set,
      # see #columns, and `mode`, which `validate_rows` replaces, see #validate_rows.
      def self.removed_option_names
        super + %w[allowed_columns required_columns skip_unknown header_cleanser columns mode]
      end

      # Returns [String] the message that says that the supplied options were removed, see
      # Category::Base.removed_options_message, and for `mode`, what to use instead.
      def self.removed_options_message(names)
        return super unless names.include?("mode")

        mode = "mode: was removed in Rocket Job v8: use validate_rows: true in place of mode: :hash, which parses " \
               "each row of a file in the category's format when it is uploaded, and remove mode: :array, since the " \
               "workers parse the lines of a file in the category's format, see #{VALIDATE_ROWS_GUIDE}"
        names == ["mode"] ? mode : "#{super(names - ['mode'])}. #{mode}"
      end

      # Returns [true|false] whether the supplied value of the named removed option is set, rather than blank, or at its
      # default, see Category::Base.removed_options: `skip_unknown` when true, `header_cleanser` when :none, and `mode`
      # when it is not blank or :line, so that a value that Rocket Job 7 did not accept either, such as :hashes, raises
      # too, otherwise when it is not blank.
      def self.removed_option_set?(name, value)
        case name
        when "skip_unknown"
          [true, "true"].include?(value)
        when "header_cleanser"
          value.to_s == "none"
        when "mode"
          value.present? && value.to_s != "line"
        else
          super
        end
      end
      private_class_method :removed_option_set?

      # Returns [Hash] the supplied properties of this category that a Dirmon entry or an UploadFileJob saved before
      # Rocket Job v8, see Category::Base#convert_saved_properties, with the `mode` that v8 removed replaced by the
      # `validate_rows` that replaces it, as for a category that Rocket Job 7 saved, see #convert_saved_mode. This
      # category is the one that the properties are merged into, see #merge_properties, so its format and
      # `validate_rows` apply when the properties do not set them. The keys of converted properties are Strings, as
      # they are saved.
      #
      # Any other `mode`, such as :array, is kept, so that the properties are reported as not valid, see
      # #property_errors.
      def convert_saved_properties(properties)
        mode = properties["mode"] || properties[:mode]
        return properties unless CONVERTED_MODES.include?(mode.to_s)

        properties    = properties.stringify_keys.except("mode")
        validate_rows = properties.key?("validate_rows") ? properties["validate_rows"] : self.validate_rows
        format        = properties.key?("format") ? properties["format"] : self.format
        properties["validate_rows"] = true if mode_validates_rows?(mode, format, validate_rows)
        properties
      end

      # Yields each record of the supplied records of a slice of this category, as `#perform` receives it. The rows of a
      # file, see IOStreams::Slice, are read by IOStreams by the header row and format that they carry, with this
      # category's schema when it has one, see #schema. Otherwise each record is parsed on its own, see #parse. A blank
      # row is nil.
      #
      # A record that cannot be parsed raises before it is yielded, after the records before it, so that the caller
      # knows which record failed.
      #
      # Raises ArgumentError when this category was saved before Rocket Job v8 with an option that v8 removed, see
      # Category::Base#check_removed_options, which is checked once for each instance of the category, rather than for
      # each slice that a worker processes, since the options that a saved category holds do not change.
      def parse_records(records, &)
        # Records that are not the rows of a slice, such as those that the block of an upload without a format writes,
        # are each parsed on their own. A slice yields each row alone to a block of one argument.
        return records.each { |record| yield parse(record) } unless records.is_a?(IOStreams::Slice)
        return parse_rows(records, &) if rows_parsed_alone?(records)

        @removed_options_checked ||= check_removed_options || true
        IOStreams.stream(records).schema(schema_descriptor).each(:hash, &)
      end

      # Returns the supplied record of a slice of this category as `#perform` receives it: parsed in this category's
      # format, see #parse_record, or as it is when the category has no format. A blank record of a tabular format is
      # nil.
      def parse(record)
        return record if record.nil? || !tabular?
        return if record.blank?

        parse_record(record)
      end

      # Returns [Hash|Array|String] the record uploaded into this category, parsed for `#perform`.
      #
      # A Hash was parsed when it was uploaded, for example by Rocket Job 7 in :hash mode, or by the application with
      # `upload_slice`, so it is kept as it is with a schema, otherwise only narrowed to the columns, when they are set.
      # A record of a category with a schema that is not a Hash, such as one that `upload_slice` uploaded, is read by
      # the schema, so it needs a format without a header row, such as JSON or fixed width, since the slices of a file
      # hold its header row instead, see #parse_records.
      def parse_record(record)
        if record.is_a?(Hash)
          return record if schema.present?

          return tabular.header.to_hash(record)
        end

        if tabular.header?
          raise(ArgumentError,
                "The tabular header columns _must_ be set before attempting to parse data that requires it.")
        end

        schema.present? ? tabular.record_parse(record) : tabular.read_record(record)
      end

      def data_store(job)
        RocketJob::Sliced::Input.new(
          collection_name: build_collection_name(:input, job),
          slice_class:     serializer_class,
          slice_size:      slice_size
        )
      end

      # Returns [IOStreams::Path] of file to upload.
      # Auto-detects file format from file name when format is :auto.
      def upload_path(stream = nil, original_file_name: nil)
        unless stream || file_name
          raise(ArgumentError, "Either supply a file name to upload, or set input_collection.file_name first")
        end

        path           = IOStreams.new(stream || file_name)
        path.file_name = original_file_name if original_file_name
        self.file_name = path.file_name

        detect_format(path)

        # Read the file in this category's encoding, unless the caller set one on the path, see #encoding.
        apply_encoding(path)

        # Read tabular input in its format, so that IOStreams reads it in the format's encoding, such as ASCII for
        # fixed width, and splits its lines where the format expects. An encoding set on the supplied path is kept,
        # since only the caller knows how the file was written.
        if tabular?
          path.format(format)
          # The fields of the records, and the position of each field of a fixed width file, so that IOStreams matches
          # the header row to the fields, and reads typed values in their columns, see #copy_slices. The schema is read
          # once, see #schema_descriptor, for the workers too, which read each slice with it, see #parse_records, so that
          # another schema cannot be set on the supplied path, also when this category has none.
          check_path_schema(path)
          path.schema(schema_descriptor) if schema.present?
          path.encoding(cleaner: upload_cleaner)
        end
        apply_invalid_characters(path)
        path
      end

      # Writes the file that the supplied path reads, see #upload_path, to the supplied store of slices, see
      # Sliced::Writer::Input, in slices of up to `slice_size` rows, as IOStreams reads them, see
      # `IOStreams::Stream#each(:slice)`:
      # - In a format whose rows are lines of text, such as CSV or JSON, the lines of the file, after its header row,
      #   which IOStreams matches to the fields of the schema, when there is one, so that a file whose columns do not
      #   match raises IOStreams::Errors::InvalidHeader before any slice. Each slice carries the header row of its file,
      #   so that more than one file can be uploaded into this category, and the workers read each row by it, see
      #   #parse_records.
      # - In a format whose rows are values, such as :hash or Parquet, the typed records of the file, as IOStreams reads
      #   them, in a store of the :hash format, or the rows of the :array format, see #typed_target.
      # - Without a format, each line of the file, as it is, with its line, in the IOStreams :lines format, since the
      #   records of this category are not parsed, see #parse, also when the file name gives a format, such as `.csv`.
      #   A spreadsheet, whose rows IOStreams reads as CSV text, raises ArgumentError, since its rows are not lines.
      #
      # When `validate_rows` is true, see #upload_validates_rows?, IOStreams also parses each row before its slice is
      # written, so that a file with a value that is not valid raises before it is processed. Each slice still holds
      # the rows as they are.
      #
      # Raises ArgumentError when this category cannot read a file, see #slice_target.
      def copy_slices(path, writer, validate_rows: nil)
        validate = upload_validates_rows?(validate_rows)
        return slice_target(writer).copy_from(path, mode: :line, validate: validate) if formatted?
        return typed_target(writer).copy_from(path, mode: typed_mode, validate: validate) if tabular?

        # The :lines format holds each line as it is, also when the file name gives a format, such as `.csv`.
        IOStreams.stream(writer).copy_from(path.format(:lines), mode: :line)
      end

      # Writes the rows of the supplied stream of a query, such as of an Active Record relation, see `IOStreams.stream`,
      # to the supplied store of slices, see Sliced::Writer::Input: in this category's format, such as the lines of CSV
      # after the names of the columns, as a file of the query would hold them, by this category's schema, otherwise by
      # the schema of the columns of the query, so that the workers read them as the rows of a file. Without a format,
      # IOStreams holds the typed values of each row after the names of the columns, see #rows_target, and the record
      # of each row is the value of its column when it has one, otherwise an Array of its values, see #parse_rows.
      def copy_rows(stream, writer)
        detect_format(file_name)
        rows_target(writer).copy_from(stream, mode: :array)
      end

      # Yields the writer of the rows of a query, such as of a Mongoid criteria, see Sliced::Input#upload_mongo_query,
      # which takes the names of the columns first, with `#write_header(columns)`, and then each row as an Array of its
      # values, with `<<`, which IOStreams writes to the supplied store of slices, see Sliced::Writer::Input, as
      # #copy_rows does.
      def write_rows(writer, &)
        detect_format(file_name)
        rows_target(writer).writer(:array, &)
      end

      # Yields to the supplied block of an upload, see RocketJob::Batch::IO#upload, the writer of the lines of a file,
      # such as its header row followed by its rows, which IOStreams writes to the supplied store of slices, see
      # Sliced::Writer::Input, as it reads the slices of a file, see #copy_slices: the header row is read from the first
      # lines, and matched to the fields of the schema, and each slice holds it. A format of :auto is replaced with that
      # of the file name of the upload, otherwise CSV, as for a file, see #upload_path.
      #
      # IOStreams reads the lines as UTF-8 text, as it reads a file: a line in another encoding, such as Windows-1252, is
      # converted to UTF-8, and the bytes of a binary line are read as UTF-8. Each character that is not valid in its
      # line's encoding is removed or replaced, or raises IOStreams::Errors::InvalidEncoding, as #invalid_characters
      # says. The error names the byte offset and line that reading the lines from a file would, counting the header
      # row, and nothing is uploaded. Each row is then cleaned as the text of a file is, see #upload_cleaner.
      #
      # When `validate_rows` is true, see #upload_validates_rows?, IOStreams also parses each line, after the header row,
      # before its slice is written.
      #
      # In a format whose rows are values, the block writes Hashes, for :hash and Parquet, or for :array, Arrays after a
      # header row, which IOStreams holds as they are, see #typed_target. Without a format, the block writes each record
      # as it is, whatever it is, to the store of slices itself, see Sliced::Writer::Input#<<, which `#perform`
      # receives, see #parse.
      #
      # Raises ArgumentError for a record written to the writer that is not a line, such as a Hash, in a format whose
      # rows are lines, and when this category cannot read the lines, see #slice_target.
      def write_slices(writer, validate_rows: nil, &)
        # Records written without a format can be any object, such as an Integer or nil, so they are written as they
        # are, to the store of slices itself, see Sliced::Writer::Input#<<.
        return yield(writer) unless tabular?

        detect_format(file_name)
        validate = upload_validates_rows?(validate_rows)
        return typed_target(writer).writer(typed_mode, validate: validate, &) unless formatted?

        target      = slice_target(writer).encoding(cleaner: upload_cleaner)
        replacement = invalid_character_replacement
        target.encoding(replace: replacement) if replacement
        target.writer(:line, validate: validate, &)
      end

      # Returns [true|false] whether an upload into this category parses each row of its file as it uploads it: the
      # supplied `validate_rows:` of the upload, unless it is nil, otherwise this category's, see #validate_rows. Always
      # false without a format, which has no rows to parse.
      def upload_validates_rows?(validate_rows = nil)
        tabular? && validate_rows_setting(validate_rows) == true
      end

      # Raises ArgumentError when a file, or the lines that the block of an upload writes, cannot be uploaded into this
      # category with the supplied `validate_rows:` of the upload, see #upload_validates_rows?: when it is not true,
      # false or nil, or when it, or else this category's `validate_rows`, is true without a format, which has no rows
      # to validate, or when this category was saved before Rocket Job v8 with a mode that v8 did not convert, such as
      # :array, see #convert_saved_mode, also without a format. The other options that v8 removed only raise in a
      # format, see Category::Base#check_removed_options, since they had no effect without one.
      def check_upload(validate_rows = nil)
        unless [nil, true, false].include?(validate_rows)
          raise(ArgumentError, "Input category #{name}: validate_rows: must be true or false, not #{validate_rows.inspect}")
        end

        check_removed_options(attributes.slice("mode"))
        return if tabular? || !validate_rows_setting(validate_rows)

        raise(ArgumentError, "Input category #{name}: validate_rows: needs a format, whose rows it validates, such as " \
                             ":auto, which reads a file in the format of its file name")
      end

      # Raises ArgumentError when this category cannot parse the records of the supplied kind of object, such as a range,
      # whose records are `[first_id, last_id]`, rather than the rows of a file: in a format whose header row is still
      # to be read, such as CSV, see #parse_record. Otherwise every slice would fail once a worker parsed it. The rows of
      # a query are written in the format instead, see #copy_rows.
      def check_record_upload(kind)
        return unless tabular? && tabular.header?

        raise(ArgumentError, "Input category #{name}: cannot upload #{kind} in the #{format.inspect} format, which " \
                             "reads the header row of a file. Upload it into a category without a format")
      end

      # Yields to upload a file into this category, see RocketJob::Batch::IO#upload. When the upload raises, its records
      # are not kept, so the fields that it set are restored, see #upload_state, such as the format that :auto was
      # replaced with, and the file can be uploaded again, such as when the job is retried.
      def uploading
        state = upload_state
        yield
      rescue Exception
        restore_upload_state(state)
        raise
      end

      # Returns [Hash] the fields that an upload sets, see #restore_upload_state: the file name, and the format that
      # :auto is replaced with.
      def upload_state
        UPLOAD_FIELDS.to_h { |name| [name, attributes[name]] }
      end

      # Sets the fields that an upload sets to the supplied ones, see #upload_state, so that the category is as it was
      # before the uploads since, whose records were removed.
      def restore_upload_state(state)
        UPLOAD_FIELDS.each { |name| public_send(:"#{name}=", state[name]) }
      end

      private

      # Adds an error when `validate_rows` is true without a format, whose rows it would validate, see #validate_rows.
      def validate_rows_has_format
        errors.add(:validate_rows, "needs a format, whose rows it validates") if validate_rows && !tabular?
      end

      # Reads the `mode` that Rocket Job 7 saved in this category, which v8 removed, see .removed_option_names, as the
      # `validate_rows` that replaces it, once the category is read from the database:
      # :hash
      #   Read as `validate_rows: true` in a format, see #mode_validates_rows?, otherwise dropped.
      # :line
      #   The default, which had no effect, so it is dropped.
      # :array, or any other value
      #   Kept, so that the next run of a scheduled job is still created, and its upload raises, see #check_upload, as a
      #   worker does that reads its records in a format, see Category::Base#check_removed_options.
      #
      # The category, and so its job, is changed, as though it had been set: saving the job removes the `mode` from
      # the database, and saves the `validate_rows` that replaces it, so that it is read the same way, also once the
      # format is changed, and can be changed like any other setting.
      def convert_saved_mode
        mode = attributes["mode"]
        return unless CONVERTED_MODES.include?(mode.to_s)

        remove_attribute("mode")
        self.validate_rows = true if mode_validates_rows?(mode, format, validate_rows)
      end

      # Returns [true|false] whether the supplied `mode` that Rocket Job 7 saved, see #convert_saved_mode, is read as
      # `validate_rows: true` in a category with the supplied format and `validate_rows`: :hash in a format, unless
      # `validate_rows` was set too, which then applies, as in Rocket Job 7.1. Without a format it had no effect, as in
      # Rocket Job 7.0, which only parsed a file into Hashes for the `stream_mode: :hash` of `#upload`.
      def mode_validates_rows?(mode, format, validate_rows)
        mode.to_s == "hash" && format.present? && validate_rows.nil?
      end

      # Returns [true|false|nil] the supplied `validate_rows:` of an upload, unless it is nil, otherwise this category's,
      # see #validate_rows, which is nil when neither is set, see #upload_validates_rows?.
      def validate_rows_setting(validate_rows)
        validate_rows.nil? ? self.validate_rows : validate_rows
      end

      # Replaces a format of :auto with the format of the supplied path, which its file name gives, otherwise CSV, so
      # that an upload reads its file, or the lines that its block writes, in it, see #upload_path and #write_slices.
      # Setting the format builds the tabular again.
      def detect_format(path)
        self.format = path&.format || :csv if format == :auto
      end

      # Returns [true|false] whether the rows of this category's format are lines of text, such as CSV or JSON, which a
      # file, or the block of an upload, gives as they are, see #copy_slices and #write_slices, rather than Ruby objects,
      # such as those of :hash or :array, or rows that are not lines, such as those of Parquet. A format of :auto is that
      # of the file name, otherwise CSV, see #detect_format.
      def rows_are_lines?
        format = upload_format
        IOStreams::Tabular.lines?(format) && IOStreams::Tabular.parser_class(format).value_form != :typed
      end

      # Returns [true|false] whether IOStreams writes the records of an upload into this category in its format, see
      # #copy_slices: when it has a format whose rows are lines of text. Otherwise the records are held as they are:
      # without a format, see #copy_slices and #write_slices, and in a format whose rows are values, such as :hash,
      # :array or Parquet, see #typed_target.
      def formatted?
        tabular? && rows_are_lines?
      end

      # Returns [IOStreams::Stream] that writes the records of an upload in a format whose rows are values, see
      # #formatted?: Hashes for :hash and Parquet, whose records are typed, as those of a query are, and Arrays for
      # :array, after their header row, see #typed_mode, by this category's schema, when it has one.
      def typed_target(writer)
        slice_target(writer).format(typed_mode == :array ? :array : :hash)
      end

      # Returns [Symbol] the mode that IOStreams writes the records of an upload in, in a format whose rows are values,
      # see #typed_target.
      def typed_mode
        format == :array ? :array : :hash
      end

      # Returns [IOStreams::Stream] that writes the rows of a query, see #copy_rows and #write_rows: in this category's
      # format when its rows are lines, see #formatted?, otherwise as the typed values of each row, after the names of
      # the columns, in the :array format, which #parse_rows reads.
      def rows_target(writer)
        formatted? ? slice_target(writer) : IOStreams.stream(writer).format(:array)
      end

      # Returns [true|false] whether the rows of the supplied slice are each parsed on their own, see #parse_rows, rather
      # than read by IOStreams by the header row and format that the slice carries: the lines of a file without a
      # format, in the :lines format, and the rows of a slice in a category without a format, such as those of a query
      # or the ranges of a Range. IOStreams reads every other slice, also one without a header row, such as the typed
      # rows of the :array format, by the fields of this category's schema, in order.
      def rows_parsed_alone?(slice)
        slice.format == :lines || !tabular?
      end

      # Yields the record of each row of the supplied slice, see #rows_parsed_alone?, as `#perform` receives it, see
      # #parse: in a category without a format, the row of a query of one column, see #rows_target, is its value, as
      # Rocket Job 7 uploaded it.
      def parse_rows(slice)
        value = !tabular? && slice.header&.size == 1
        slice.each { |row| yield parse(value ? row.first : row) }
      end

      # Returns [Symbol] this category's format, or the format of its file name when it is :auto, otherwise CSV, which an
      # upload replaces :auto with, see #detect_format.
      def upload_format
        format == :auto ? file_name&.format || :csv : format
      end

      # Returns [IOStreams::Stream] that writes lines to the supplied store of slices, see Sliced::Writer::Input, by this
      # category's schema, when it has one, in its format, which an upload has detected when it was :auto, see
      # #detect_format.
      #
      # Raises ArgumentError, before any line is read, when this category was saved before Rocket Job v8 with an option
      # that v8 removed, see Category::Base#check_removed_options, or, without a schema, holds columns that no upload
      # read, see #check_columns_not_set.
      def slice_target(writer)
        check_removed_options
        check_columns_not_set if schema.blank?
        IOStreams.stream(writer).schema(schema_descriptor).format(format)
      end

      # The text that replaces each character that is not valid in the file's encoding, see #invalid_characters.
      INVALID_CHARACTER_REPLACEMENTS = {remove: "", replace: "�"}.freeze
      private_constant :INVALID_CHARACTER_REPLACEMENTS

      # Raises ArgumentError when the supplied path has a schema other than this category's, which the workers read each
      # slice of the file with, see #parse_records, also when this category has none.
      def check_path_schema(path)
        return if path.schema.nil? || path.schema == schema

        raise(ArgumentError, "Set the schema of the file uploaded into input category #{name} on the category, not on " \
                             "the path, since its workers read each slice with the category's schema")
      end

      # Sets what the path does with each character that is not valid in the file's encoding, see
      # #invalid_characters, unless the caller set `replace:` on the path.
      def apply_invalid_characters(path)
        return if path.setting(:encode)&.key?(:replace)

        replacement = invalid_character_replacement
        path.encoding(replace: replacement) if replacement
      end

      # Returns [String|nil] the text that replaces each character of an upload that is not valid in its encoding, see
      # #invalid_characters, or nil when such a character raises.
      def invalid_character_replacement
        handling = invalid_characters || (tabular? && format != :fixed ? :remove : :raise)
        INVALID_CHARACTER_REPLACEMENTS[handling]
      end

      # Returns [Symbol|Proc] how an upload in this category's tabular format cleans the text of a file, see
      # #upload_path, and the lines that the block of an upload writes, see #write_slices: each non-printable character
      # other than a line ending, such as NUL padding or a tab, is replaced with a space in a fixed width format, so
      # that the columns stay in place, and removed in any other tabular format.
      def upload_cleaner
        format == :fixed ? FIXED_WIDTH_CLEANER : :printable
      end

      # Without a schema, the tabular reads the columns as the header row of a file that Rocket Job 7 uploaded, see
      # #columns, which it reads each of its lines by. With one, each slice of a file holds its header row instead, see
      # #parse_records.
      #
      # Raises ArgumentError when the columns are not the header row of a file, see #check_header_row.
      def build_tabular
        tabular = super
        return tabular if schema.present? || columns.blank?

        check_header_row(tabular)
        tabular
      end

      # Reads the columns as the header row of a file that Rocket Job 7 uploaded, see #columns, with the supplied
      # tabular, which cleanses each of them, as Rocket Job 7 cleansed them when the file was uploaded.
      #
      # Raises ArgumentError when reading them as a header row changes them, since Rocket Job v8 cannot read the lines
      # by them as Rocket Job 7 did: columns that were not cleansed, which an application set before v8 for a file
      # without a header row, see .removed_option_names.
      def check_header_row(tabular)
        tabular.read_header(columns)
        return if tabular.header.columns == columns

        raise(ArgumentError,
              "Input category #{name} holds columns that are not the header row of an uploaded file, so they are the " \
              "columns of a file without a header row: #{self.class.removed_options_message(%w[columns])}")
      end

      # Raises ArgumentError when the category holds columns, see #columns, before an upload into it without a schema
      # reads its file, which would read the first row of a file without a header row as its header row: the columns
      # of a scheduled job saved by Rocket Job 7, which copied the header row of an upload into its next run, or columns
      # set for a file without a header row, which Rocket Job v8 removed.
      def check_columns_not_set
        return if columns.blank?

        raise(ArgumentError,
              "Input category #{name} holds columns, which Rocket Job v8 never sets, so a file cannot be uploaded " \
              "into it without a schema. When Rocket Job 7 uploaded a file into this category of a job that is " \
              "still running, upload the next file into a new job, since this one reads its lines by those columns. " \
              "When Rocket Job 7 copied them from an earlier run of a scheduled job, clear them. Otherwise they are " \
              "the columns of a file without a header row: #{self.class.removed_options_message(%w[columns])}")
      end
    end
  end
end

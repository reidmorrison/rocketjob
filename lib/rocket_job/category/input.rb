module RocketJob
  module Category
    # Define the layout for each category of input or output data
    class Input
      include SemanticLogger::Loggable
      include Plugins::Document
      include Category::Base
      include Category::InputSchemaProposal

      embedded_in :job, class_name: "RocketJob::Job", inverse_of: :input_categories

      # Slice size for this input collection
      field :slice_size, type: Integer, default: 100
      validates_presence_of :slice_size

      #
      # The fields below only apply if the field `format` has been set:
      #

      # List of columns to allow.
      # Default: nil ( Allow all columns )
      # Note:
      #   When supplied any columns that are rejected will be returned in the cleansed columns
      #   as nil so that they can be ignored during processing.
      #
      # Deprecated, use `schema`, whose `fieldsMatch` says which columns a file can have.
      field :allowed_columns, type: Array

      # List of columns that must be present, otherwise an Exception is raised.
      #
      # Deprecated, use `schema`, with `constraints: {required: true}` on each field that a file must have.
      field :required_columns, type: Array

      # Whether to skip unknown columns in the uploaded file.
      # Ignores any column that was not found in the `allowed_columns` list.
      #
      # false:
      #   Raises IOStreams::Tabular::InvalidHeader when a column is supplied that is not in `allowed_columns`.
      # true:
      #   Ignore additional columns in a file that are not listed in `allowed_columns`
      #   Job processing will skip the additional columns entirely as if they were not supplied at all.
      #   A warning is logged with the names of the columns that were ignored.
      #   The `columns` field will list all skipped columns with a nil value so that downstream workers
      #   know to ignore those columns.
      #
      # Notes:
      # - Only applicable when `allowed_columns` has been set.
      # - Recommended to leave as `false` otherwise a misspelled column can result in missed columns.
      # - Deprecated, use `schema`, whose `fieldsMatch` of "subset" or "partial" skips the other columns.
      field :skip_unknown, type: ::Mongoid::Boolean, default: false
      validates_inclusion_of :skip_unknown, in: [true, false]

      # Whether `#upload` parses each line of a file in this category's format, see #format, as it uploads it, so that a
      # file with a line that cannot be read, or with a value that is not valid for its field, see #schema, uploads
      # nothing. The lines are still uploaded as they are, and parsed again by the workers, see #parse.
      #
      # Use it when the entire file must be validated before processing is started, and upload time is not important,
      # since the lines are parsed one after another while the file is uploaded.
      #
      # Needs a format. Only a file is validated: not a query or a range, which upload values rather than the lines of
      # a file, nor the records that the block of an upload writes, see RocketJob::Batch::IO#upload.
      #
      # Replaces the :hash `mode`, which is deprecated, see #mode, and is the same option in Rocket Job 8.
      #
      # Default: nil, which validates the lines of a category with a schema in the :hash `mode`, as 7.0 did. Set it to
      # false so that such a category does not validate them.
      field :validate_rows, type: ::Mongoid::Boolean
      validate :validate_rows_has_format

      # Why `validate_rows` cannot be true without a format, see #validate_rows_without_format?.
      VALIDATE_ROWS_NEEDS_FORMAT = "needs a format, whose lines it validates".freeze
      private_constant :VALIDATE_ROWS_NEEDS_FORMAT

      # When `#upload` is called with a file_name, it uploads the file using any of the following approaches:
      # :line
      #   Uploads the file a line (String) at a time for processing by workers.
      #   This is the default behavior and is the most performant since it leaves the parsing of each line
      #   up to the workers themselves.
      # :array
      #   Deprecated, use :line, and `validate_rows: true` to also parse every line when the file is uploaded.
      #   Parses each line from the file as an Array and uploads each array for processing by workers.
      #   Every line in the input file is parsed and converted into an array before uploading.
      #   This approach ensures that the entire files is valid before starting to process it.
      #   Ideal for when files may contain invalid lines.
      #   Not recommended for large files since the CSV or other parsing is performed sequentially during the
      #   upload process.
      # :hash
      #   Deprecated, use `validate_rows: true`, see #validate_rows, which Rocket Job 8 reads a saved :hash mode as.
      #   With a schema, see #schema, parses every line when it is uploaded, as `validate_rows: true` does. Without a
      #   schema it has no effect on how a file is read.
      #
      # Only the deprecated `stream_mode:` of an upload reads a file into records rather than lines: :hash without a
      # format, and :array without a schema, see #each_record. Otherwise the lines of the file are uploaded, and its
      # header row read, whatever this mode is, and the workers parse them, by the schema when there is one, so that
      # each value reaches `#perform` as its type, such as a Date. The :array mode cannot be used with a schema.
      field :mode, type: ::Mongoid::StringifiedSymbol, default: :line
      validates_inclusion_of :mode, in: %i[line array hash]

      # When reading tabular input data (e.g. CSV, PSV) the header is automatically cleansed.
      # This removes issues when the input header varies in case and other small ways. See IOStreams::Tabular
      # Currently Supported:
      #   :default
      #     Each column is cleansed as follows:
      #     - Leading and trailing whitespace is stripped.
      #     - All characters converted to lower case.
      #     - Spaces and '-' are converted to '_'.
      #     - All characters except for letters, digits, and '_' are stripped.
      #   :none
      #     Do not cleanse the columns names supplied in the header row.
      #
      # Note: Submit a ticket if you have other cleansers that you want added.
      #
      # Deprecated, use `schema`, whose fields name the keys of each record, and which the columns of the header row
      # are matched to whatever their case, spaces and punctuation.
      field :header_cleanser, type: ::Mongoid::StringifiedSymbol, default: :default
      validates :header_cleanser, inclusion: %i[default none]

      validates_inclusion_of :serializer, in: %i[none compress encrypt]

      # Reports a deprecation warning, see RocketJob::Deprecation, for the deprecated options in the supplied
      # properties of an input category, see Category::Base.warn_deprecated_options, and for its :array `mode`.
      def self.warn_deprecated_options(properties)
        super
        warn_deprecated_mode(properties.to_h.stringify_keys["mode"])
      end

      # Reports a deprecation warning, see RocketJob::Deprecation, for the supplied mode of an input category, see
      # #mode, when it is deprecated: :array, and :hash, which `validate_rows` replaces, see #validate_rows.
      def self.warn_deprecated_mode(mode)
        case mode.to_s
        when "array"
          RocketJob::Deprecation.warn(
            "mode: :array is deprecated, use :line, the default, which the workers parse, and validate_rows: true to " \
            "also parse every line when the file is uploaded, see #{RocketJob::Deprecation::UPGRADE_GUIDE}"
          )
        when "hash"
          RocketJob::Deprecation.warn(
            "mode: :hash is deprecated, use validate_rows: true instead, which parses every line of a file in the " \
            "category's format when it is uploaded, as mode: :hash did with a schema. Without a schema mode: :hash " \
            "has no effect, so remove it, since Rocket Job 8 reads it as validate_rows: true, see " \
            "#{RocketJob::Deprecation::UPGRADE_GUIDE}"
          )
        end
      end

      # Returns [Array<String>] the names of the deprecated options in the supplied properties of an input category,
      # with String keys, see Category::Base.deprecated_options, and `mode` when it is :array or :hash, see #mode.
      def self.deprecated_options(properties)
        names = super
        names << "mode" if %w[array hash].include?(properties["mode"].to_s)
        names
      end

      # Returns [Array<String>] the names of the deprecated options in the supplied properties of an input category,
      # with String keys, see Category::Base.deprecated_column_options: `allowed_columns`, `required_columns`,
      # `skip_unknown` when true, `header_cleanser` when :none, and `columns` without a schema, since with one they
      # hold the header row read from the file.
      def self.deprecated_column_options(properties)
        names = []
        names << "columns" if properties["columns"].present? && properties["schema"].blank?
        names.concat(%w[allowed_columns required_columns].select { |name| properties[name].present? })
        names << "skip_unknown" if [true, "true"].include?(properties["skip_unknown"])
        names << "header_cleanser" if properties["header_cleanser"].to_s == "none"
        names
      end

      # Cleanses the header column names when `cleanse_header` is true
      def cleanse_header!
        return unless header_cleanser == :default

        ignored_columns = tabular.header.cleanse!
        logger.warn("Stripped out invalid columns from custom header", ignored_columns) unless ignored_columns.empty?

        self.columns = tabular.header.columns
      end

      def tabular
        return @tabular ||= schema_tabular if schema.present?

        @tabular ||= IOStreams::Tabular.new(
          columns:          columns,
          format:           format == :auto ? nil : format,
          format_options:   format_options&.to_h&.deep_symbolize_keys,
          file_name:        file_name,
          allowed_columns:  allowed_columns,
          required_columns: required_columns,
          skip_unknown:     skip_unknown
        )
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

        # Auto detect the format based on the upload file name if present.
        if format == :auto
          self.format = path.format || :csv
          # Rebuild tabular with new values.
          @tabular = nil
        end

        if schema.present?
          # IOStreams reads the text of a file with a schema as UTF-8, and raises for text that is not valid UTF-8,
          # unless an encoding is set on the supplied path, which reads it instead. A schema set on the supplied path
          # is kept.
          path.schema(schema) if path.schema.nil?
        elsif tabular?
          # Remove non-printable characters from tabular input formats.
          # Cannot change the length of fixed width lines.
          replace = format == :fixed ? " " : ""
          path.encoding("UTF-8", cleaner: :printable, replace: replace)
        end
        path
      end

      # Returns the supplied record of an upload as `#perform` receives it: parsed in this category's format, or as it is
      # when the category has no format. A blank record of a tabular format is nil.
      #
      # Raises ArgumentError when the format needs a header row that has not been read yet.
      def parse(record)
        return record unless tabular?
        return if record.blank?

        if tabular.header?
          raise(ArgumentError,
                "The tabular header columns _must_ be set before attempting to parse data that requires it.")
        end

        tabular.record_parse(record)
      end

      # Returns [Array] the first records of the supplied file, or stream, as `#perform` would receive them if the file
      # were uploaded into this category, see RocketJob::Batch::IO#upload. A copy of this category reads the file, so
      # nothing is stored, and this category is not changed. Raises what the upload, or a worker parsing a record,
      # would raise.
      def preview(stream, limit: 100)
        copy    = deep_dup
        # A copy of a path, so that the encoding that an upload sets on it does not change the caller's.
        path    = copy.upload_path(stream.is_a?(IOStreams::Stream) ? stream.dup : stream)
        header  = copy.extract_header_callback(nil)
        records = []
        # Each record is parsed below, as a worker parses it, so it is not also parsed while it is read.
        copy.each_record(path, validate_rows: false) do |record|
          if header
            header = nil if header.call(record)
            next
          end
          records << copy.parse(record)
          break if records.size >= limit
        end
        records
      end

      # Yields each record read from the supplied path for an upload, see RocketJob::Batch::IO#upload: each line, which
      # is first parsed in this category's format when it validates the rows of the file, see #upload_validates_rows?,
      # with the supplied `validate_rows:` of the upload, so that a line that cannot be read, or a value that is not
      # valid, raises before any record is processed.
      #
      # The supplied mode, the deprecated `stream_mode:` of the upload, decides alone whether the lines are parsed: in
      # the :hash mode each line is parsed first, as with `validate_rows: true`. It reads the file into records instead
      # of lines, as 7.0 read it, see `IOStreams::Stream#each`, only where 7.0 could upload them, see
      # #stream_mode_records?.
      def each_record(path, mode: nil, validate_rows: nil, **args, &)
        mode = mode&.to_sym
        return path.each(mode, **args, &) if stream_mode_records?(mode)

        if schema.present? && (mode || self.mode) == :array
          raise(ArgumentError,
                "Input category #{name} has a schema, which cannot be uploaded in :array mode, use :line, and " \
                "validate_rows: true to also parse every line when the file is uploaded")
        end
        validate = mode ? mode == :hash : upload_validates_rows?(validate_rows)
        return path.each(:line, **args, &) unless validate

        path.each(:line, **args) do |line|
          # The lines before the header row, and the header row itself, are read by #extract_header_callback, and a
          # blank line is not parsed, since a worker does not parse one either, see #parse.
          tabular.record_parse(line) unless line.blank? || tabular.header?
          yield(line)
        end
      end

      # Returns [true|false] whether an upload of a file into this category parses each line of it as it uploads it,
      # see #validate_rows: the supplied `validate_rows:` of the upload, unless it is nil, otherwise this category's,
      # unless it is nil too, otherwise whether this category has a schema and the :hash `mode`, which 7.0 parsed each
      # line in. Always false without a format, which has no lines to parse.
      def upload_validates_rows?(validate_rows = nil)
        return false unless tabular?

        validate_rows = self.validate_rows if validate_rows.nil?
        validate_rows.nil? ? schema.present? && mode == :hash : validate_rows
      end

      # Raises ArgumentError when a file cannot be uploaded into this category with the supplied `validate_rows:` of the
      # upload, see #upload_validates_rows?: when it is not true, false or nil, or when it, or else this category's
      # `validate_rows`, is true without a format, which has no lines to validate.
      def check_upload(validate_rows = nil)
        unless [nil, true, false].include?(validate_rows)
          raise(ArgumentError, "Input category #{name}: validate_rows: must be true or false, not #{validate_rows.inspect}")
        end
        return unless validate_rows_without_format?(validate_rows.nil? ? self.validate_rows : validate_rows)

        raise(ArgumentError, "Input category #{name}: validate_rows: #{VALIDATE_ROWS_NEEDS_FORMAT}, such as :auto, which " \
                             "reads a file in the format of its file name")
      end

      # Reports a deprecation warning, see RocketJob::Deprecation, for the supplied `stream_mode:` of an upload into
      # this category, see RocketJob::Batch::IO#upload, which Rocket Job 8 removes, saying what replaces it here: an
      # explicit `stream_mode:` decides alone whether the lines are parsed, see #each_record.
      def warn_deprecated_stream_mode(stream_mode)
        RocketJob::Deprecation.warn(
          "stream_mode: #{stream_mode.inspect} is deprecated, and removed in Rocket Job 8: " \
          "#{stream_mode_replacement(stream_mode.to_s)}, see #{RocketJob::Deprecation::UPGRADE_GUIDE}"
        )
      end

      # Returns the lambda that the upload calls with each record before the first that it stores, instead of storing
      # it, until the lambda returns true, see `Sliced::Writer::Input`: it reads the header row, when the file has one,
      # then calls the supplied `on_first` with it. Otherwise it calls `on_first` with the first record. Returns nil
      # when there is neither.
      #
      # A blank line before the header row is skipped, as IOStreams skips it when it reads the header row itself, such
      # as in :hash mode, so that the header row is not stored as a record.
      #
      # The header row is read whatever the mode, see #mode, since a file in a format is uploaded in lines, or in the
      # :array `stream_mode:` of an upload, as an Array, which IOStreams also reads as a header row, see #each_record.
      def extract_header_callback(on_first)
        return schema_header_callback(on_first) if schema.present?
        return first_record_callback(on_first) unless tabular? && tabular.header?

        lambda do |line|
          next false if line.blank?

          tabular.parse_header(line)
          cleanse_header!
          self.columns = tabular.header.columns
          # Call chained on_first if present
          on_first&.call(line)
          true
        end
      end

      private

      # Returns [IOStreams::Tabular] that reads the records of this category by its schema, see Category::Base#schema,
      # and has read the header row that an upload read from the file, see #columns, so that the workers parse each line
      # by it.
      def schema_tabular
        tabular = super
        tabular.read_header(columns) if columns.present? && tabular.header?
        tabular
      end

      # Returns the lambda that reads the header row of a file with a schema, see #extract_header_callback. Its columns
      # are matched to the fields of the schema, which raises IOStreams::Errors::InvalidHeader when they do not match,
      # and are kept as they are in the file, see #columns. A blank row before it, which IOStreams does not read as a
      # header row, such as a line of only commas, is skipped, as IOStreams skips it when it reads the header row itself.
      #
      # With a schema, `columns` hold the header row of the file uploaded, so an upload reads the header row of its own
      # file, rather than keep the columns of an earlier one, such as those that a job scheduled again copies from its
      # last run, see Plugins::Cron.
      def schema_header_callback(on_first)
        self.columns = nil
        @tabular     = nil
        return first_record_callback(on_first) unless tabular.header?

        lambda do |line|
          tabular.read_header(line)
          next false if tabular.header?

          self.columns = tabular.header.columns
          # Call chained on_first if present
          on_first&.call(line)
          true
        end
      end

      # The schema describes the columns of the file, so the options that describe them without one cannot be set with
      # it, see Category::Base#schema.
      def fields_replaced_by_schema
        replaced = super + %i[allowed_columns required_columns].select { |name| public_send(name).present? }
        replaced << :skip_unknown if skip_unknown
        replaced << :header_cleanser if header_cleanser == :none
        replaced
      end

      # Returns [true|false] whether the supplied `validate_rows` is true without a format, whose lines it validates.
      def validate_rows_without_format?(validate_rows)
        validate_rows == true && !tabular?
      end

      # Adds an error when `validate_rows` is true without a format, see #validate_rows_without_format?.
      def validate_rows_has_format
        errors.add(:validate_rows, VALIDATE_ROWS_NEEDS_FORMAT) if validate_rows_without_format?(validate_rows)
      end

      # Returns [true|false] whether the supplied `stream_mode:` of an upload reads a file into records rather than
      # lines, see #each_record: without a schema, :array, whose rows IOStreams reads a header row from, and :hash
      # without a format, which reads each line into a Hash in the format of the file name. In a format, :hash uploads
      # the lines, whose header row is read, see #extract_header_callback, and which the workers parse, since a Hash
      # cannot be read as a header row, nor parsed by the format.
      def stream_mode_records?(mode)
        schema.blank? && (mode == :array || (mode == :hash && !tabular?))
      end

      # Returns [String] what replaces the supplied `stream_mode:` of an upload into this category, see
      # #warn_deprecated_stream_mode.
      def stream_mode_replacement(stream_mode)
        if %w[hash array].include?(stream_mode) && !tabular?
          "give the category format: :auto in place of stream_mode: :#{stream_mode}, so that the workers read each " \
            "line into a Hash, in the format of the file name"
        elsif stream_mode == "hash"
          "use validate_rows: true in place of stream_mode: :hash, to parse every line of the file in the category's " \
            "format when it is uploaded"
        elsif stream_mode == "array"
          "remove it, so that the workers parse the lines in the category's format, and use validate_rows: true to " \
            "also parse every line when the file is uploaded"
        elsif upload_validates_rows?
          "use validate_rows: false in its place, since the category parses every line of a file when it is " \
            "uploaded, which stream_mode: :line does not"
        else
          "remove it, since :line is the default"
        end
      end

      # The :array mode cannot be used with a schema, see #mode.
      def schema_replaces_fields
        super
        return unless schema.present? && mode == :array

        errors.add(:mode, "cannot be :array with a schema, use :line, and validate_rows: true to parse every line")
      end

      # Returns the lambda that calls the supplied `on_first` with the first record uploaded, which is not stored, see
      # #extract_header_callback, or nil without one.
      def first_record_callback(on_first)
        return unless on_first

        lambda do |record|
          on_first.call(record)
          true
        end
      end
    end
  end
end

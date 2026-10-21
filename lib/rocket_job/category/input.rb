module RocketJob
  module Category
    # Define the layout for each category of input or output data
    class Input
      include SemanticLogger::Loggable
      include Plugins::Document
      include Category::Base

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

      # When `#upload` is called with a file_name, it uploads the file using any of the following approaches:
      # :line
      #   Uploads the file a line (String) at a time for processing by workers.
      #   This is the default behavior and is the most performant since it leaves the parsing of each line
      #   up to the workers themselves.
      # :array
      #   Deprecated, use :line, or with a schema :hash, which also parses every line when the file is uploaded.
      #   Parses each line from the file as an Array and uploads each array for processing by workers.
      #   Every line in the input file is parsed and converted into an array before uploading.
      #   This approach ensures that the entire files is valid before starting to process it.
      #   Ideal for when files may contain invalid lines.
      #   Not recommended for large files since the CSV or other parsing is performed sequentially during the
      #   upload process.
      # :hash
      #   Parses each line from the file into a Hash and uploads each hash for processing by workers.
      #   Similar to :array above in that the entire file is parsed before processing is started.
      #   Slightly less efficient than :array since it stores every record as a hash with both the key and value.
      #
      # Use :hash with a schema when the entire file must be parsed/validated before processing is started, and upload
      # time is not important. Without a schema, a category with a format whose files have a header row, such as CSV,
      # cannot be uploaded in the :hash mode.
      # See IOStreams#each for more details.
      #
      # With a schema, see #schema, the lines of the file are uploaded in the :line and :hash modes, which the workers
      # parse by the schema, so that each value reaches `#perform` as its type, such as a Date. In :hash mode every line
      # is also parsed when it is uploaded, so that a file with a value that is not valid is not uploaded at all. The
      # :array mode cannot be used with a schema.
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
        warn_array_mode if properties.to_h.stringify_keys["mode"].to_s == "array"
      end

      # Reports a deprecation warning, see RocketJob::Deprecation, for the :array mode of an upload, see #mode, set as
      # the supplied option, such as the `stream_mode:` of `upload`.
      def self.warn_array_mode(option = :mode)
        RocketJob::Deprecation.warn(
          "#{option}: :array is deprecated, use :line, the default, which the workers parse, or with a schema :hash, " \
          "which also parses every line when the file is uploaded, see #{RocketJob::Deprecation::UPGRADE_GUIDE}"
        )
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

      # Yields each record read from the supplied path for an upload, see RocketJob::Batch::IO#upload, in the supplied
      # mode, otherwise in :line mode, see `IOStreams::Stream#each`.
      #
      # With a schema it yields the lines of the file in the supplied mode, otherwise in this category's mode, see
      # #mode, and in :hash mode parses each line after the header row by the schema first, so that a value that is not
      # valid raises before any record is processed.
      def each_record(path, mode: nil, **args, &)
        return path.each(mode || :line, **args, &) if schema.blank?

        mode ||= self.mode
        if mode == :array
          raise(ArgumentError,
                "Input category #{name} has a schema, which cannot be uploaded in :array mode, use :line or :hash")
        end
        return path.each(:line, **args, &) if mode == :line

        path.each(:line, **args) do |line|
          # The lines before the header row, and the header row itself, are read by #extract_header_callback.
          tabular.record_parse(line) unless tabular.header?
          yield(line)
        end
      end

      # Returns the lambda that the upload calls with each record before the first that it stores, instead of storing
      # it, until the lambda returns true, see `Sliced::Writer::Input`: it reads the header row, when the file has one,
      # then calls the supplied `on_first` with it. Otherwise it calls `on_first` with the first record. Returns nil
      # when there is neither.
      #
      # A blank line before the header row is skipped, as IOStreams skips it when it reads the header row itself, such
      # as in :hash mode, so that the header row is not stored as a record.
      def extract_header_callback(on_first)
        return schema_header_callback(on_first) if schema.present?
        return first_record_callback(on_first) unless tabular? && tabular.header?

        case mode
        when :line
          lambda do |line|
            next false if line.blank?

            tabular.parse_header(line)
            cleanse_header!
            self.columns = tabular.header.columns
            # Call chained on_first if present
            on_first&.call(line)
            true
          end
        when :array
          lambda do |row|
            tabular.header.columns = row
            cleanse_header!
            self.columns = category.tabular.header.columns
            # Call chained on_first if present
            on_first&.call(line)
          end
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

      # The :array mode cannot be used with a schema, see #mode.
      def schema_replaces_fields
        super
        errors.add(:mode, "cannot be :array with a schema, use :line or :hash") if schema.present? && mode == :array
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

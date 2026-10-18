module RocketJob
  module Category
    # Define the layout for each category of input or output data
    class Input
      include SemanticLogger::Loggable
      include Plugins::Document
      include Category::Base

      embedded_in :job, class_name: "RocketJob::Job", inverse_of: :input_categories

      # The fields that an upload sets, see #upload_state.
      UPLOAD_FIELDS = %w[file_name format columns header_uploaded].freeze
      private_constant :UPLOAD_FIELDS

      # Replaces each non-printable character, other than line endings, with a space.
      FIXED_WIDTH_CLEANER = ->(data, _replace) { data.gsub(/[^[:print:]\r\n]/, " ") }
      private_constant :FIXED_WIDTH_CLEANER

      # Slice size for this input collection
      field :slice_size, type: Integer, default: 100
      validates_presence_of :slice_size

      #
      # The fields below only apply if the field `format` has been set.
      #
      # With a schema, see #schema, `columns` holds the columns of the header row read from the uploaded file, as they
      # are in the file, which IOStreams matches to the fields of the schema, so that the workers parse each line by
      # them. The other fields below are deprecated, since the schema replaces them, and cannot be set with it.
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
      #   Deprecated, use :line, or :hash to parse the whole file when it is uploaded.
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
      # Use :hash when the entire file must be parsed/validated before processing is started, and upload time is not
      # important.
      # See IOStreams#each for more details.
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

      # What `#upload` does with each character of a file that is not valid in the file's encoding, see #encoding:
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
      # A `replace:` set on the path supplied to `#upload` is used instead.
      # Default: nil
      field :invalid_characters, type: ::Mongoid::StringifiedSymbol
      validates_inclusion_of :invalid_characters, in: [nil, :remove, :replace, :raise]

      # Whether `columns` hold the header row that an upload read from its file, see #read_header, rather than columns
      # set for a file without a header row. The category holds the header row of one file, which the workers read
      # each of its lines by, so another file with a header row cannot be uploaded into it, see
      # #extract_header_callback, and the next run of a restarted job reads the header row of its own file, see
      # #restart_copy.
      #
      # Default: false, which is also what a job saved before v8 reads.
      field :header_uploaded, type: ::Mongoid::Boolean, default: false

      validates_inclusion_of :serializer, in: %i[none compress encrypt]

      # Setting a field that the tabular is built from builds it again when it is next used, see #tabular.
      %i[allowed_columns required_columns skip_unknown header_cleanser].each do |name|
        define_method(:"#{name}=") do |value|
          @tabular = nil
          super(value)
        end
      end

      # Returns [RocketJob::Category::Input] a copy of this category for the next run of its job, see
      # Category::Base#restart_copy, without the header row that an upload read from the file, see #header_uploaded, so
      # that the next run reads the header row of its own file.
      def restart_copy
        copy = super
        return copy unless header_uploaded?

        copy.columns         = nil
        copy.header_uploaded = false
        copy
      end

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
          "#{option}: :array is deprecated, use :line, the default, which the workers parse, or :hash to parse the " \
          "whole file when it is uploaded, see #{RocketJob::Deprecation::UPGRADE_GUIDE}"
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

      # Treats the current columns as a header row read from the file: matches them to the fields of the schema, see
      # #schema, otherwise cleanses their names when `header_cleanser` is :default, and applies `allowed_columns`,
      # `required_columns` and `skip_unknown`.
      def cleanse_header!
        read_header(columns)
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
      # A Hash was parsed when it was uploaded, for example in :hash mode, by the schema when there is one, so it is
      # kept as it is, otherwise only narrowed to the columns, when they are set. For a format whose records supply
      # their own keys, such as JSON, the schema, or the column restrictions, are applied to each record's keys.
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

        # Auto detect the format based on the upload file name if present, which builds the tabular again.
        self.format = path.format || :csv if format == :auto

        # Read the file in this category's encoding, unless the caller set one on the path, see #encoding.
        apply_encoding(path)

        # Read tabular input in its format, so that IOStreams reads it in the format's encoding, such as ASCII for
        # fixed width, and splits its lines where the format expects. An encoding set on the supplied path is kept,
        # since only the caller knows how the file was written.
        if tabular?
          path.format(format)
          # The fields of the records, and the position of each field of a fixed width file, so that the :array and
          # :hash modes read typed values in their columns, see #each_record. A schema, or a layout, set on the supplied
          # path is kept.
          if path.schema.nil?
            path.schema(schema) if schema.present?
            path.format_options(format_options.to_h.deep_symbolize_keys) if format_options.present?
          end
          # Replace the non-printable characters of a fixed width file, such as NUL padding, so that the columns stay
          # in place, and remove those of any other tabular format.
          path.encoding(cleaner: format == :fixed ? FIXED_WIDTH_CLEANER : :printable)
        end
        apply_invalid_characters(path)
        path
      end

      # Yields each record read from the supplied path in the supplied mode, see #mode.
      #
      # In :hash mode IOStreams reads the header row, and applies the column restrictions, since the header row
      # is not yielded. In :array mode the header row is yielded, and read by #extract_header_callback.
      def each_record(path, mode: self.mode, **args, &)
        path.each(mode, **read_options(mode), **args, &)
      end

      # Returns the lambda to call with the first record uploaded, that reads the header row, when the upload
      # starts with one, see #header_first?, otherwise the supplied `on_first`.
      #
      # When the columns were supplied they take the place of a header row, so the column restrictions are
      # applied to them now. With a schema they were matched to its fields when the tabular was built, see
      # #build_tabular. In :hash mode IOStreams applies them instead, see #each_record.
      #
      # Raises ArgumentError when the category already holds the header row of a file, see #header_uploaded, since the
      # lines of another file could not be read by it.
      #
      # Raises ArgumentError also in :hash mode, since its records would be narrowed to the columns of that header row
      # when they are parsed, see #parse_record.
      def extract_header_callback(on_first, mode: self.mode)
        return on_first unless tabular?

        if header_uploaded?
          raise(ArgumentError,
                "Input category #{name} already holds the header row of an uploaded file, which its lines are read " \
                "by. Upload each file with a header row into its own input category, or upload every file in the " \
                ":hash mode")
        end
        return on_first if mode == :hash

        unless header_first?(mode)
          restrict_columns! if schema.blank?
          return on_first
        end

        lambda do |row|
          self.header_uploaded = true if read_header(row)
          # Call chained on_first if present
          on_first&.call(row)
        end
      end

      # Yields to upload a file into this category, see RocketJob::Batch::IO#upload. When the upload raises, its records
      # are not kept, so the fields that it set are restored, see #upload_state, such as the columns that the header
      # row it read replaced, see #header_uploaded, and the file can be uploaded again, such as when the job is retried.
      def uploading
        state = upload_state
        yield
      rescue Exception
        restore_upload_state(state)
        raise
      end

      # Returns [Hash] the fields that an upload sets, see #restore_upload_state: the file name, the format that
      # :auto is replaced with, and the columns of the header row that it reads, see #header_uploaded.
      def upload_state
        UPLOAD_FIELDS.to_h { |name| [name, attributes[name]] }
      end

      # Sets the fields that an upload sets to the supplied ones, see #upload_state, so that the category is as it was
      # before the uploads since, whose records were removed.
      def restore_upload_state(state)
        UPLOAD_FIELDS.each { |name| public_send(:"#{name}=", state[name]) }
      end

      private

      # The text that replaces each character that is not valid in the file's encoding, see #invalid_characters.
      INVALID_CHARACTER_REPLACEMENTS = {remove: "", replace: "�"}.freeze
      private_constant :INVALID_CHARACTER_REPLACEMENTS

      # Sets what the path does with each character that is not valid in the file's encoding, see
      # #invalid_characters, unless the caller set `replace:` on the path.
      def apply_invalid_characters(path)
        return if path.setting(:encode)&.key?(:replace)

        handling    = invalid_characters || (tabular? && format != :fixed ? :remove : :raise)
        replacement = INVALID_CHARACTER_REPLACEMENTS[handling]
        path.encoding(replace: replacement) if replacement
      end

      # With a schema, also matches the columns of the header row read from the file, see #columns, to its fields, so
      # that each line uploaded is parsed by them. Without one, the tabular reads the header row in the same way, see
      # #header_row_tabular.
      def build_tabular
        tabular = header_row_tabular || super
        tabular.read_header(columns) if schema.present? && columns.present? && tabular.header?
        tabular
      end

      # Returns [IOStreams::Tabular] that has read the header row that an upload read from a file without a schema, see
      # #columns, as it reads a header row, rather than with the deprecated `columns:` option of IOStreams, so that a
      # category that sets no deprecated option reports no deprecation warning when a worker parses its records.
      #
      # Returns nil when the category sets a deprecated option, or when reading the columns as a header row would not
      # keep them as they are, such as columns that the application set without cleansing them, which the deprecated
      # option then keeps.
      def header_row_tabular
        return unless schema.blank? && format_options.blank? && columns.present? && column_restrictions.empty? &&
                      cleanse_header?

        tabular = IOStreams::Tabular.new(format: tabular_format, file_name: file_name)
        return unless tabular.header?

        tabular.read_header(columns)
        tabular if tabular.header.columns == columns
      end

      # Returns [Hash] the deprecated options of IOStreams::Tabular for the columns of the file, see
      # Category::Base#tabular_columns, with the column restrictions, when they are set, and `cleanse_header: false`
      # when `header_cleanser` is :none, so that the tabular reads the header row, the supplied columns, and the keys
      # of each record without cleansing them.
      def tabular_columns
        return super if schema.present?

        options = super.merge(column_restrictions)
        options[:cleanse_header] = false unless cleanse_header?
        options
      end

      # Returns [Hash] the column restrictions, which are deprecated, when they are set.
      def column_restrictions
        return {} if allowed_columns.blank? && required_columns.blank?

        {
          allowed_columns:  allowed_columns.presence,
          required_columns: required_columns.presence,
          skip_unknown:     skip_unknown
        }.compact
      end

      # Its `columns` hold the header row read from a file with a schema, see #columns, so the schema does not
      # replace them.
      def fields_replaced_by_schema
        replaced = super + %i[allowed_columns required_columns].select { |name| public_send(name).present? }
        replaced << :skip_unknown if skip_unknown
        replaced << :header_cleanser unless cleanse_header?
        replaced
      end

      def cleanse_header?
        header_cleanser == :default
      end

      # Returns [true|false] whether the first record uploaded in the supplied mode is a header row: the header row of a
      # file with one, such as CSV, or in :array mode, the header row that IOStreams yields before the rows of a file
      # without one, which names their columns: the keys of the first record of JSON without a schema, or the names of
      # the fields of a schema, such as of fixed width, see `IOStreams::Tabular#rows_header?`.
      def header_first?(mode)
        mode == :array ? tabular.rows_header? : tabular.header?
      end

      # Reads the header row. With a schema IOStreams matches its columns to the fields, and they are kept as they are
      # in the file, see #columns. Otherwise it is cleansed, unless `header_cleanser` is :none, and the column
      # restrictions are applied to it, see #tabular_columns and `IOStreams::Tabular#read_header`.
      #
      # Returns [true|nil] whether a header row was read: a blank row with a schema is not one.
      def read_header(row)
        if schema.present?
          return if row.blank?

          columns = tabular.parser.parse(row)
          tabular.read_header(columns)
          # Kept without building the tabular again, which has read them.
          self[:columns] = columns
        else
          tabular.read_header(row)
          header_read
        end
        true
      end

      # Applies the column restrictions to the supplied columns, see `IOStreams::Tabular#restrict_columns`, which
      # cleanses them as the tabular does, see #tabular_columns.
      def restrict_columns!
        tabular.restrict_columns
        header_read
      end

      def header_read
        # Kept without building the tabular again, which has read them.
        self[:columns] = tabular.header.columns
        rejected = columns&.select { |column| column.start_with?(IOStreams::Tabular::Header::IGNORE_PREFIX) }
        logger.warn("Stripped out invalid columns from custom header", rejected) if rejected.present?
      end

      # Returns [Hash] the deprecated options for IOStreams to read records in the supplied mode, when they are set. The
      # format and schema are set on the path instead, see #upload_path.
      def read_options(mode)
        return {} if mode == :line || !tabular? || schema.present?

        options = {columns: columns.presence}
        if mode == :hash
          options.merge!(column_restrictions)
          options[:cleanse_header] = false unless cleanse_header?
        end
        options.compact
      end
    end
  end
end

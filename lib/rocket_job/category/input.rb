module RocketJob
  module Category
    # Define the layout for each category of input or output data
    class Input
      include SemanticLogger::Loggable
      include Plugins::Document
      include Category::Base

      embedded_in :job, class_name: "RocketJob::Job", inverse_of: :input_categories

      autoload :UploadSlices, "rocket_job/category/input/upload_slices"
      autoload :WrittenLines, "rocket_job/category/input/written_lines"
      private_constant :UploadSlices, :WrittenLines

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
      # With a schema, see #schema, each slice of an uploaded file holds its header row, see #each_slice, so `columns`
      # is not set. The fields below are deprecated, since the schema replaces them, and cannot be set with it.
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

      # Returns [Array<String>] the names of the deprecated options that the supplied properties of an input category
      # set, see Category::Base.deprecated_option_names, and its `mode` when it is the deprecated :array. The `columns`
      # that an upload read from the header row of a file, see #header_uploaded, are left out, since the application
      # did not set them.
      def self.deprecated_option_names(properties)
        properties = properties.to_h.stringify_keys
        names      = super
        names.delete("columns") if [true, "true"].include?(properties["header_uploaded"])
        names << "mode" if properties["mode"].to_s == "array"
        names
      end

      # Returns [Array<String>] the names of the deprecated options in the supplied properties of an input category,
      # with String keys, see Category::Base.deprecated_column_options: `columns`, `allowed_columns`,
      # `required_columns`, `skip_unknown` when true, and `header_cleanser` when :none.
      def self.deprecated_column_options(properties)
        names = super
        names.concat(%w[allowed_columns required_columns].select { |name| properties[name].present? })
        names << "skip_unknown" if [true, "true"].include?(properties["skip_unknown"])
        names << "header_cleanser" if properties["header_cleanser"].to_s == "none"
        names
      end

      # Treats the current columns as a header row read from the file: cleanses their names when `header_cleanser` is
      # :default, and applies `allowed_columns`, `required_columns` and `skip_unknown`.
      def cleanse_header!
        read_header(columns)
      end

      # Yields each record of the supplied records of a slice of this category, as `#perform` receives it. The rows of a
      # file, see IOStreams::Slice, are read by IOStreams by the header row and format that they carry, with this
      # category's schema, see #schema. Otherwise each record is parsed on its own, see #parse. A blank row is nil.
      #
      # A record that cannot be parsed raises before it is yielded, after the records before it, so that the caller
      # knows which record failed.
      def parse_records(records, &)
        return records.each { |record| yield parse(record) } unless records.is_a?(IOStreams::Slice)

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
      # A Hash was parsed when it was uploaded, for example in :hash mode without a schema, or by the application with
      # `upload_slice`, so it is kept as it is with a schema, otherwise only narrowed to the columns, when they are set.
      # A record of a category with a schema that is not a Hash, such as one that `upload_slice` uploaded, is read by
      # the schema, so it needs a format without a header row, such as JSON or fixed width, since the slices of a file
      # hold its header row instead, see #parse_records. For a format whose records supply their own keys, such as
      # JSON, the column restrictions are applied to each record's keys.
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
          # The fields of the records, and the position of each field of a fixed width file, so that IOStreams matches
          # the header row to the fields, and reads typed values in their columns, see #each_slice and #each_record. The
          # schema is read once, see #schema_descriptor, for the workers too, which read each slice with it, see
          # #parse_records, so that another schema cannot be set on the supplied path. Without a schema, a schema set on
          # the supplied path is kept.
          if schema.present?
            check_path_schema(path)
            path.schema(schema_descriptor)
          end
          # Replace the non-printable characters of a fixed width file, such as NUL padding, so that the columns stay
          # in place, and remove those of any other tabular format.
          path.encoding(cleaner: format == :fixed ? FIXED_WIDTH_CLEANER : :printable)
        end
        apply_invalid_characters(path)
        path
      end

      # Returns [true|false] whether a file is uploaded into this category in slices of its rows, which carry the header
      # row of their file and its format, see #each_slice: when it has a schema, which describes the columns of its
      # files. Otherwise each record is uploaded on its own, see #each_record, and parsed by the columns that this
      # category holds, see #parse.
      def slices?
        tabular? && schema.present?
      end

      # Yields each slice of up to `slice_size` rows of the file that the supplied path reads, see #upload_path, as
      # IOStreams reads them, see `IOStreams::Stream#each(:slice)`: after its header row, which IOStreams matches to the
      # fields of the schema, so that a file whose columns do not match raises IOStreams::Errors::InvalidHeader before
      # any slice. Each slice carries the header row of its file, so that more than one file can be uploaded into this
      # category, and the workers read each row by it, see #parse_records.
      #
      # In the :hash and the deprecated :array modes, see #mode, IOStreams also parses each row as it reads it, so that a
      # file with a value that is not valid raises before it is processed. Each slice still holds the rows as they are.
      #
      # `on_first` is called with the header row, see UploadSlices.
      def each_slice(path, mode: self.mode, on_first: nil, **args, &)
        slices = UploadSlices.new(on_first, &)
        path.reader(:slice, size: slice_size, validate: mode != :line, **args) do |reader|
          reader.each { |slice| slices << slice }
          slices.finish(reader.header)
        end
      end

      # Yields a writer to the supplied block of an upload, see RocketJob::Batch::IO#upload, to which the block writes the
      # lines of a file, such as its header row followed by its rows, and yields each slice of them, as IOStreams reads
      # the slices of a file, see #each_slice and WrittenLines: the header row is read from the first lines, and matched
      # to the fields of the schema, and each slice holds it. `on_first` is called with the header row, see
      # UploadSlices.
      #
      # Raises ArgumentError for a record written to the writer that is not a line, such as a Hash.
      def each_written_slice(block, on_first: nil, &)
        slices = UploadSlices.new(on_first, &)
        WrittenLines.new(build_tabular, slices, size: slice_size, validate: mode != :line).write(block)
      end

      # Yields each record read from the supplied path in the supplied mode, see #mode.
      #
      # In :hash mode IOStreams reads the header row, and applies the column restrictions, since the header row
      # is not yielded. In :array mode the header row is yielded, and read by #extract_header_callback.
      def each_record(path, mode: self.mode, **args, &)
        path.each(mode, **read_options(mode), **args, &)
      end

      # Returns the lambda that the upload calls with each record before the first that it stores, instead of storing
      # it, until the lambda returns true, see `Sliced::Writer::Input`: it reads the header row, when the upload starts
      # with one, see #header_first?, then calls the supplied `on_first` with it. Otherwise it calls `on_first` with the
      # first record. Returns nil when there is neither. In :hash mode IOStreams reads the header row itself, so
      # `on_first` is not called for a file with one, as in v7, and every record is uploaded.
      #
      # A blank line before the header row is skipped, as IOStreams skips it when it reads the header row itself, such
      # as in :hash mode, so that the header row is not stored as a record.
      #
      # When the columns were supplied they take the place of a header row, so the column restrictions are
      # applied to them now. In :hash mode IOStreams applies them instead, see #each_record. A category with a schema
      # uploads slices instead, see #each_slice.
      #
      # Raises ArgumentError when the category already holds the header row of a file, see #header_uploaded, since the
      # lines of another file could not be read by it.
      #
      # Raises ArgumentError also in :hash mode, since its records would be narrowed to the columns of that header row
      # when they are parsed, see #parse_record.
      def extract_header_callback(on_first, mode: self.mode)
        first_record = first_record_callback(on_first)
        return first_record unless tabular?

        if header_uploaded?
          raise(ArgumentError,
                "Input category #{name} already holds the header row of an uploaded file, which its lines are read " \
                "by. Upload each file with a header row into its own input category, or upload every file in the " \
                ":hash mode")
        end
        # IOStreams reads the header row itself in :hash mode, see #each_record.
        return tabular.header? ? nil : first_record if mode == :hash

        unless header_first?(mode)
          restrict_columns!
          return first_record
        end

        lambda do |row|
          next false if row.blank?

          read_header(row)
          self.header_uploaded = true
          # Call chained on_first if present
          on_first&.call(row)
          true
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

      # Raises ArgumentError when the supplied path has a schema other than this category's, which the workers read each
      # slice of the file with, see #parse_records.
      def check_path_schema(path)
        return if path.schema.nil? || path.schema == schema

        raise(ArgumentError, "Set the schema of the file uploaded into input category #{name} on the category, not on " \
                             "the path, since its workers read each slice with the category's schema")
      end

      # Sets what the path does with each character that is not valid in the file's encoding, see
      # #invalid_characters, unless the caller set `replace:` on the path.
      def apply_invalid_characters(path)
        return if path.setting(:encode)&.key?(:replace)

        handling    = invalid_characters || (tabular? && format != :fixed ? :remove : :raise)
        replacement = INVALID_CHARACTER_REPLACEMENTS[handling]
        path.encoding(replace: replacement) if replacement
      end

      # Without a schema, the tabular reads the header row that an upload read from the file as a header row, see
      # #header_row_tabular. With one, each slice of a file holds its header row instead, see #parse_records.
      def build_tabular
        header_row_tabular || super
      end

      # Returns [IOStreams::Tabular] that has read the header row that an upload read from a file without a schema, see
      # #columns, as it reads a header row, rather than with the deprecated `columns:` option of IOStreams, so that a
      # category that sets no deprecated option reports no deprecation warning when a worker parses its records.
      #
      # Returns nil when the category sets a deprecated option, or when reading the columns as a header row would not
      # keep them as they are, such as columns that the application set without cleansing them, which the deprecated
      # option then keeps.
      def header_row_tabular
        return unless schema.blank? && columns.present? && column_restrictions.empty? && cleanse_header?

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

      # Each slice of a file uploaded with a schema holds its header row, see #each_slice, so the schema replaces
      # `columns` too, as it does on an output category.
      def fields_replaced_by_schema
        replaced = super + %i[columns allowed_columns required_columns].select { |name| public_send(name).present? }
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

      # Returns the lambda that calls the supplied `on_first` with the first record uploaded, which is not stored, see
      # #extract_header_callback, or nil without one.
      def first_record_callback(on_first)
        return unless on_first

        lambda do |record|
          on_first.call(record)
          true
        end
      end

      # Reads the header row of a category without a schema: cleansed, unless `header_cleanser` is :none, with the
      # column restrictions applied to it, see #tabular_columns and `IOStreams::Tabular#read_header`. A category with a
      # schema uploads slices instead, which hold the header row of their file, see #each_slice.
      def read_header(row)
        tabular.read_header(row)
        header_read
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
        return {} if mode == :line || !tabular?

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

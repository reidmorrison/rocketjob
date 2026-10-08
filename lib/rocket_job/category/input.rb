module RocketJob
  module Category
    # Define the layout for each category of input or output data
    class Input
      include SemanticLogger::Loggable
      include Plugins::Document
      include Category::Base

      embedded_in :job, class_name: "RocketJob::Job", inverse_of: :input_categories

      # Replaces each non-printable character, other than line endings, with a space.
      FIXED_WIDTH_CLEANER = ->(data, _replace) { data.gsub(/[^[:print:]\r\n]/, " ") }
      private_constant :FIXED_WIDTH_CLEANER

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
      field :allowed_columns, type: Array

      # List of columns that must be present, otherwise an Exception is raised.
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
      field :skip_unknown, type: ::Mongoid::Boolean, default: false
      validates_inclusion_of :skip_unknown, in: [true, false]

      # When `#upload` is called with a file_name, it uploads the file using any of the following approaches:
      # :line
      #   Uploads the file a line (String) at a time for processing by workers.
      #   This is the default behavior and is the most performant since it leaves the parsing of each line
      #   up to the workers themselves.
      # :array
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
      # Recommend using :array when the entire file must be parsed/validated before processing is started, and
      # upload time is not important.
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
      field :header_cleanser, type: ::Mongoid::StringifiedSymbol, default: :default
      validates :header_cleanser, inclusion: %i[default none]

      validates_inclusion_of :serializer, in: %i[none compress encrypt]

      # Treats the current columns as a header row read from the file: cleanses their names when
      # `header_cleanser` is :default, and applies `allowed_columns`, `required_columns` and `skip_unknown`.
      def cleanse_header!
        read_header(columns)
      end

      # Returns [Hash|Array|String] the record uploaded into this category, parsed for `#perform`.
      #
      # A Hash was parsed when it was uploaded, for example in :hash mode, so it is only narrowed to the
      # columns, when they are set. For a format whose records supply their own keys, such as JSON, the
      # column restrictions are applied to each record's keys.
      def parse_record(record)
        return tabular.header.to_hash(record) if record.is_a?(Hash)

        if tabular.header?
          raise(ArgumentError,
                "The tabular header columns _must_ be set before attempting to parse data that requires it.")
        end

        tabular.read_record(record, rename: cleanse_header?)
      end

      def tabular
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

        # Read tabular input in its format, so that IOStreams reads it in the format's encoding, such as ASCII for
        # fixed width, and splits its lines where the format expects. An encoding set on the supplied path is kept,
        # since only the caller knows how the file was written.
        if tabular?
          path.format(format)
          if format == :fixed
            # Replace non-printable characters, such as NUL padding, so that the columns stay in place. A character
            # that is not valid in the file's encoding still raises, unless the caller supplied `replace:`.
            path.encoding(cleaner: FIXED_WIDTH_CLEANER)
          else
            # Remove non-printable characters, and characters that are not valid in the file's encoding.
            path.encoding(cleaner: :printable, replace: "")
          end
        end
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
      # starts with one, otherwise the supplied `on_first`.
      #
      # When the columns were supplied they take the place of a header row, so the column restrictions are
      # applied to them now. In :hash mode IOStreams applies them instead, see #each_record.
      def extract_header_callback(on_first, mode: self.mode)
        return on_first unless tabular? && mode != :hash

        unless tabular.header?
          restrict_columns!
          return on_first
        end

        lambda do |row|
          read_header(row)
          # Call chained on_first if present
          on_first&.call(row)
        end
      end

      private

      def cleanse_header?
        header_cleanser == :default
      end

      # Reads the header row, cleansing it and applying the column restrictions, see `IOStreams::Tabular#read_header`.
      def read_header(row)
        tabular.read_header(row, cleanse: cleanse_header?)
        header_read
      end

      # Applies the column restrictions to the supplied columns, see `IOStreams::Tabular#restrict_columns`.
      def restrict_columns!
        tabular.restrict_columns(rename: cleanse_header?)
        header_read
      end

      def header_read
        self.columns = tabular.header.columns
        rejected     = columns&.select { |column| column.start_with?(IOStreams::Tabular::Header::IGNORE_PREFIX) }
        logger.warn("Stripped out invalid columns from custom header", rejected) if rejected.present?
      end

      # Returns [Hash] the options for IOStreams to read records in the supplied mode.
      def read_options(mode)
        return {} if mode == :line || !tabular?

        options = {format: tabular.format, format_options: format_options&.to_h&.deep_symbolize_keys, columns: columns}
        if mode == :hash
          options.merge!(
            allowed_columns:  allowed_columns,
            required_columns: required_columns,
            skip_unknown:     skip_unknown,
            cleanse_header:   cleanse_header?
          )
        end
        options.compact
      end
    end
  end
end

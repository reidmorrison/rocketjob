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

      validates_presence_of :slice_size

      # Cleanses the header column names when `cleanse_header` is true
      def cleanse_header!
        return unless header_cleanser == :default

        ignored_columns = tabular.header.cleanse!
        logger.warn("Stripped out invalid columns from custom header", ignored_columns) unless ignored_columns.empty?

        self.columns = tabular.header.columns
      end

      def tabular
        @tabular ||= IOStreams::Tabular.new(
          columns:          columns,
          format:           format == :auto ? nil : format,
          format_options:   format_options&.deep_symbolize_keys,
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
    end
  end
end

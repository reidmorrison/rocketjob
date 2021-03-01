module RocketJob
  module Category
    # Define the layout for each category of input or output data
    class Input < Base
      include SemanticLogger::Loggable

      attr_accessor :mode, :allowed_columns, :required_columns, :skip_unknown, :cleanse_header

      # Parameters:
      #   serializer: [:compress|:encrypt|:bzip2]
      #     Whether to compress, encrypt, or use the bzip2 serialization for data in this category.
      #     Overrides the jobs `.compress`, or `.encrypt` options if any.
      #
      #   columns [Array<String>]
      #     The header columns when the file does not include a header row.
      #     Note:
      #       All column names must be strings so that it can be serialized into MongoDB.
      #
      #   format: [Symbol]
      #     :csv, :hash, :array, :json, :psv, :fixed
      #     Default: `nil`, no transformation is performed on the data returned by the `#perform` method.
      #
      #   format_options: [Hash]
      #     Any specialized format specific options. For example, `:fixed` format requires the file definition.
      #
      #   file_name: [String]
      #     When `:format` is not supplied the file name can be used to infer the required format.
      #     Optional. Default: nil
      #
      #   allowed_columns [Array<String>]
      #     List of columns to allow.
      #     Default: nil ( Allow all columns )
      #     Note:
      #       When supplied any columns that are rejected will be returned in the cleansed columns
      #       as nil so that they can be ignored during processing.
      #
      #   required_columns [Array<String>]
      #     List of columns that must be present, otherwise an Exception is raised.
      #
      #   skip_unknown [true|false]
      #     true:
      #       Skip columns not present in the `allowed_columns` by cleansing them to nil.
      #       #as_hash will skip these additional columns entirely as if they were not in the file at all.
      #     false:
      #       Raises Tabular::InvalidHeader when a column is supplied that is not in the whitelist.
      #
      #   mode: [:line | :array | :hash]
      #     :line
      #       Uploads the file a line (String) at a time for processing by workers.
      #     :array
      #       Parses each line from the file as an Array and uploads each array for processing by workers.
      #     :hash
      #       Parses each line from the file into a Hash and uploads each hash for processing by workers.
      #     See IOStreams#each.
      #
      #   cleanse_header: [true|false]
      #     Whether to cleans the input header?
      #     Removes issues when the input header varies in case and other small ways. See IOStreams::Tabular
      #     Default: true
      def initialize(mode: :line,
                     allowed_columns: nil,
                     required_columns: nil,
                     skip_unknown: false,
                     cleanse_header: true,
                     **args)
        super(**args)

        @mode             = deserialize(mode)
        @allowed_columns  = deserialize(allowed_columns)
        @required_columns = deserialize(required_columns)
        @skip_unknown     = skip_unknown
        @cleanse_header   = cleanse_header
      end

      # Cleanses the header column names when `cleanse_header` is true
      def cleanse_header!
        return unless cleanse_header

        ignored_columns = tabular.header.cleanse!
        logger.warn("Stripped out invalid columns from custom header", ignored_columns) unless ignored_columns.empty?

        self.columns = tabular.header.columns
      end

      def tabular
        @tabular ||= IOStreams::Tabular.new(
          columns:          columns,
          format:           format == :auto ? nil : format,
          format_options:   format_options,
          file_name:        file_name,
          allowed_columns:  allowed_columns,
          required_columns: required_columns,
          skip_unknown:     skip_unknown
        )
      end

      # Converts an object of this instance into a database friendly value.
      def mongoize
        h                     = super
        h["mode"]             = serialize(mode) if mode != :line
        h["allowed_columns"]  = serialize(allowed_columns) if allowed_columns
        h["required_columns"] = serialize(required_columns) if required_columns
        h["skip_unknown"]     = skip_unknown if skip_unknown
        h["cleanse_header"]   = cleanse_header unless cleanse_header
        h
      end
    end
  end
end

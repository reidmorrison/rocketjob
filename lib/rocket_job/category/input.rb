module RocketJob
  module Category
    # Define the layout for each category of input or output data
    class Input
      include SemanticLogger::Loggable
      include Plugins::Document
      include Category::Base

      embedded_in :job, class_name: "RocketJob::Job", inverse_of: :input_categories

      # Slice size for this input collection
      field :slice_size, type: Integer #, default: 100

      #   allowed_columns [Array<String>]
      #     List of columns to allow.
      #     Default: nil ( Allow all columns )
      #     Note:
      #       When supplied any columns that are rejected will be returned in the cleansed columns
      #       as nil so that they can be ignored during processing.
      field :allowed_columns, type: Array

      #   required_columns [Array<String>]
      #     List of columns that must be present, otherwise an Exception is raised.
      field :required_columns, type: Array

      #   skip_unknown [true|false]
      #     true:
      #       Skip columns not present in the `allowed_columns` by cleansing them to nil.
      #       #as_hash will skip these additional columns entirely as if they were not in the file at all.
      #     false:
      #       Raises Tabular::InvalidHeader when a column is supplied that is not in the whitelist.
      field :skip_unknown, type: ::Mongoid::Boolean

      #   mode: [:line | :array | :hash]
      #     :line
      #       Uploads the file a line (String) at a time for processing by workers.
      #     :array
      #       Parses each line from the file as an Array and uploads each array for processing by workers.
      #     :hash
      #       Parses each line from the file into a Hash and uploads each hash for processing by workers.
      #     See IOStreams#each.
      field :mode, type: ::Mongoid::StringifiedSymbol, default: :line

      #   cleanse_header: [true|false]
      #     Whether to cleans the input header?
      #     Removes issues when the input header varies in case and other small ways. See IOStreams::Tabular
      #     Default: Apply default cleansing rules
      #     nil: Don't perform header cleansing
      field :header_cleanser, type: ::Mongoid::StringifiedSymbol, default: :default

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
          format_options:   format_options,
          file_name:        file_name,
          allowed_columns:  allowed_columns,
          required_columns: required_columns,
          skip_unknown:     skip_unknown
        )
      end
    end
  end
end

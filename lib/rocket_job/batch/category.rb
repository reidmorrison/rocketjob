module RocketJob
  module Batch
    # Define the layout for each category of input or output data
    class Category
      attr_accessor :name, :serializer, :file_name, :columns, :format, :format_options, :mode,
                    :allowed_columns, :required_columns, :skip_unknown

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
      def initialize(name:,
                     serializer: nil,
                     file_name: nil,
                     columns: nil,
                     format: nil,
                     format_options: nil,
                     mode: nil,
                     allowed_columns: nil,
                     required_columns: nil,
                     skip_unknown: nil)
        serializer = deserialize(serializer)

        if [nil, :compress, :encrypt, :bzip2].exclude?(serializer)
          raise(ArgumentError, "serialize: #{serializer.inspect} must be nil, :compress, :encrypt, or :bzip2")
        end

        @serializer       = serializer
        @columns          = deserialize(columns)
        @format           = deserialize(format)
        @format_options   = deserialize(format_options)
        @mode             = deserialize(mode)
        @name             = deserialize(name)
        @allowed_columns  = deserialize(allowed_columns)
        @required_columns = deserialize(required_columns)
        @skip_unknown     = deserialize(skip_unknown)
        @file_name        = file_name
      end

      # Return which slice serializer class to use that matches the current options.
      # Notes:
      #  - The `default_encrypt` and `default_compress` options are only used when the serializer is nil.
      def serializer_class(default_encrypt: false, default_compress: false)
        case serializer
        when nil
          if default_encrypt
            Sliced::EncryptedSlice
          elsif default_compress
            Sliced::CompressedSlice
          else
            Sliced::Slice
          end
        when :compress
          Sliced::CompressedSlice
        when :encrypt
          Sliced::EncryptedSlice
        when :bzip2
          Sliced::BZip2OutputSlice
        else
          raise(ArgumentError, "serialize: #{serializer.inspect} must be nil, :compress, :encrypt, or :bzip2")
        end
      end

      # Converts an object of this instance into a database friendly value.
      def mongoize
        h                   = {}
        h["name"]           = serialize(name)
        h["serializer"]     = serialize(serializer) if serializer
        h["file_name"]      = serialize(file_name) if file_name
        h["columns"]        = serialize(columns) if columns
        h["format"]         = serialize(format) if format
        h["format_options"] = serialize(format_options) if format_options
        h["mode"]           = serialize(mode) if mode
        h
      end

      def tabular
        @tabular ||= IOStreams::Tabular.new(
          columns:        columns,
          format:         format,
          format_options: format_options,
          file_name:      file_name
        )
      end

      # Returns [true|false] whether this category has the attributes defined for tabular to work.
      def tabular?
        format.present? || file_name.present?
      end

      # Renders [String] the header line.
      # Returns [nil] if no header is needed.
      def render_header
        return unless tabular?

        tabular.render_header if tabular.requires_header?
      end

      private

      def serialize(value)
        case value
        when true
          true
        when false
          false
        when nil
          nil
        when Array
          value.collect { |val| val.is_a?(Symbol) ? val.to_s : val }
        when Hash
          h = {}
          value.each_pair do |key, val|
            key    = key.to_s if key.is_a?(Symbol)
            val    = val.to_s if val.is_a?(Symbol)
            h[key] = val
          end
          value.symbolize_keys!
          h
        else
          value.to_s
        end
      end

      def deserialize(value)
        case value
        when true
          true
        when false
          false
        when nil
          nil
        when Array
          value.collect { |val| val.is_a?(Symbol) ? val.to_s : val }
        when Hash
          h = {}
          value.each_pair do |key, val|
            key    = key.to_sym if key.is_a?(String)
            val    = val.to_sym if val.is_a?(String)
            h[key] = val
          end
          value.symbolize_keys!
          h
        else
          value.to_sym
        end
      end
    end
  end
end

module RocketJob
  module Category
    # Define the layout for each category of input or output data
    class Base
      attr_accessor :name, :serializer, :file_name, :columns, :format, :format_options

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
      def initialize(name: :main,
                     serializer: nil,
                     file_name: nil,
                     columns: nil,
                     format: nil,
                     format_options: nil)
        serializer = deserialize(serializer)

        if [nil, :compress, :encrypt, :bzip2].exclude?(serializer)
          raise(ArgumentError, "serialize: #{serializer.inspect} must be nil, :compress, :encrypt, or :bzip2")
        end

        @name             = deserialize(name)
        @serializer       = serializer
        @columns          = deserialize(columns)
        @format           = deserialize(format)
        @format_options   = deserialize(format_options)
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

      # Converts an object of this instance into a database friendly value.
      def mongoize
        h                   = {}
        h["name"]           = serialize(name)
        h["serializer"]     = serialize(serializer) if serializer
        h["file_name"]      = serialize(file_name) if file_name
        h["columns"]        = serialize(columns) if columns
        h["format"]         = serialize(format) if format
        h["format_options"] = serialize(format_options) if format_options
        h
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

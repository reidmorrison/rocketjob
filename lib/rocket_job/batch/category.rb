module RocketJob
  module Batch
    # Define the layout for each category of input or output data
    class Category
      attr_accessor :name, :serializer, :file_name, :columns, :format, :options, :mode

      # Parameters:
      #   serializer: [:compress|:encrypt|:bzip2]
      #     Whether to compress, encrypt, or use the bzip2 serialization for data in this category.
      #     Overrides the jobs `.compress`, or `.encrypt` options if any.
      #
      #   columns: [Array]
      #     List of columns to use as the header for this layout.
      #     Used by Tabular when present.
      #
      #   format: [Symbol]
      #     Any format supported by Tabular. Example: :csv, :psv, etc.
      #     Used by Tabular when present.
      #
      #   options: [Hash]
      #     Any format options supported by tabular.
      #     Used by Tabular when present.
      #
      #   mode: [:line | :array | :hash]
      #     :line
      #       Uploads the file a line (String) at a time for processing by workers.
      #     :array
      #       Parses each line from the file as an Array and uploads each array for processing by workers.
      #     :hash
      #       Parses each line from the file into a Hash and uploads each hash for processing by workers.
      #     See IOStreams#each.
      def initialize(name:, serializer: nil, file_name: nil, columns: nil, format: nil, options: nil, mode: nil)
        serializer = deserialize(serializer)

        if [nil, :compress, :encrypt, :bzip2].exclude?(serializer)
          raise(ArgumentError, "serialize: #{serializer.inspect} must be nil, :compress, :encrypt, or :bzip2")
        end

        @serializer = serializer
        @columns    = deserialize(columns)
        @format     = deserialize(format)
        @options    = deserialize(options)
        @mode       = deserialize(mode)
        @name       = deserialize(name)
        @file_name  = file_name
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
        h               = {}
        h["name"]       = serialize(name)
        h["serializer"] = serialize(serializer) if serializer
        h["file_name"]  = serialize(file_name) if file_name
        h["columns"]    = serialize(columns) if columns
        h["format"]     = serialize(format) if format
        h["options"]    = serialize(options) if options
        h["mode"]       = serialize(mode) if mode
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

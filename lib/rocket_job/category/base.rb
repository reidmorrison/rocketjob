require "active_support/concern"

module RocketJob
  module Category
    # Define the layout for each category of input or output data
    module Base
      extend ActiveSupport::Concern

      included do
        field :name, type: ::Mongoid::StringifiedSymbol, default: :main

        # Whether to compress, encrypt, or use the bzip2 serialization for data in this category.
        #     Overrides the jobs `.compress`, or `.encrypt` options if any.
        field :serializer, type: ::Mongoid::StringifiedSymbol
        # validates nil, :compress|:encrypt|:bzip2

        #     The header columns when the file does not include a header row.
        #     Note:
        #       All column names must be strings so that it can be serialized into MongoDB.
        field :columns, type: Array

        #
        #     Default: `nil`, no transformation is performed on the data returned by the `#perform` method.
        field :format, type: ::Mongoid::StringifiedSymbol
        # validates nil, :csv, :hash, :array, :json, :psv, :fixed

        #   format_options: [Hash]
        #     Any specialized format specific options. For example, `:fixed` format requires a `:layout`.
        field :format_options, type: Hash

        #   file_name: [String]
        #     When `:format` is not supplied the file name can be used to infer the required format.
        #     Optional. Default: nil
        field :file_name, type: IOStreams::Path
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
          format:         format == :auto ? nil : format,
          format_options: format_options,
          file_name:      file_name
        )
      end

      def reset_tabular
        @tabular = nil
      end

      # Returns [true|false] whether this category has the attributes defined for tabular to work.
      def tabular?
        format.present?
      end
    end
  end
end

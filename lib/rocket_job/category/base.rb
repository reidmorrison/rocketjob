require "active_support/concern"

module RocketJob
  module Category
    # Define the layout for each category of input or output data
    module Base
      extend ActiveSupport::Concern

      included do
        field :name, type: ::Mongoid::StringifiedSymbol, default: :main

        # Whether to compress, encrypt, or use the bzip2 serialization for data in this category.
        field :serializer, type: ::Mongoid::StringifiedSymbol, default: :compress

        # The header columns when the file does not include a header row.
        # Note:
        # - All column names must be strings so that it can be serialized into MongoDB.
        field :columns, type: Array

        # On an input collection `format` specifies the format of the input data so that it can be
        # transformed into a Hash when passed into the `#perform` method.
        #
        # On an output collection `format` specifies the format to transform the output hash into.
        #
        # `:auto` it uses the `file_name` on this category to determine the format.
        # `nil` no transformation is performed on the data returned by the `#perform` method.
        # Any other format supported by IOStreams, for example: csv, :hash, :array, :json, :psv, :fixed
        #
        # Default: `nil`
        field :format, type: ::Mongoid::StringifiedSymbol
        validates_inclusion_of :format, in: [nil, :auto] + IOStreams::Tabular.registered_formats

        # Any specialized format specific options. For example, `:fixed` format requires a `:layout`.
        field :format_options, type: Hash

        # When `:format` is not supplied the file name can be used to infer the required format.
        # Optional.
        # Default: nil
        field :file_name, type: IOStreams::Path
      end

      # Return which slice serializer class to use that matches the current options.
      def serializer_class
        case serializer
        when :none
          Sliced::Slice
        when :compress
          Sliced::CompressedSlice
        when :encrypt
          Sliced::EncryptedSlice
        when :bzip2, :bz2
          Sliced::BZip2OutputSlice
        when :encrypted_bz2
          Sliced::EncryptedBZip2OutputSlice
        else
          raise(ArgumentError, "serialize: #{serializer.inspect} must be :none, :compress, :encrypt, :bz2, or :encrypted_bz2")
        end
      end

      def tabular
        @tabular ||= IOStreams::Tabular.new(
          columns:        columns,
          format:         format == :auto ? nil : format,
          format_options: format_options&.to_h&.deep_symbolize_keys,
          file_name:      file_name
        )
      end

      # Returns [true|false] whether this category has the attributes defined for tabular to work.
      def tabular?
        format.present?
      end

      def build_collection_name(direction, job)
        collection_name = "rocket_job.#{direction}s.#{job.id}"
        collection_name << ".#{name}" unless name == :main
        collection_name
      end
    end
  end
end

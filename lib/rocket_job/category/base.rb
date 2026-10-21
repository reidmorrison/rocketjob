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
        # - With a schema, see #schema, the columns of an input category hold the header row read from the uploaded
        #   file, see RocketJob::Category::Input, and those of an output category cannot be set.
        # - Deprecated without a schema, use `schema`, whose fields are the columns, with `"header": false` for a file
        #   without a header row.
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
        validates_inclusion_of :format, in: [nil, :auto] + IOStreams.tabular_formats

        # Any specialized format specific options. For example, `:fixed` format requires a `:layout`.
        #
        # Deprecated, use `schema`, see #schema, which gives the width of each field of a fixed width file. It cannot be
        # set with a schema.
        field :format_options, type: Hash

        # The fields of the records in this category and the type of each one, as a Frictionless Table Schema, see
        # https://datapackage.org/standard/table-schema/, so that records are read as typed values, such as an Integer,
        # a BigDecimal or a Date, and written in the text form of each type, for every tabular format. It also gives
        # the position of each field of a fixed width file, with its `width`, and `"header": false` describes a file
        # without a header row. See `IOStreams::Schema`, and `IOStreams::Stream#schema`.
        #
        # A Hash, or the path or url of a JSON file that holds the schema, which is read when the category is first
        # used to read or write records.
        #
        # Example, for a fixed width file:
        #   {"fields" => [{"name" => "name", "type" => "string", "width" => 10},
        #                 {"name" => "zip", "type" => "integer", "width" => 5}]}
        #
        # The schema describes the columns of the file, so `format_options` and `columns` cannot be set with it, nor on
        # an input category `allowed_columns`, `required_columns`, `skip_unknown` and `header_cleanser`. It needs a
        # `format`, such as `:csv`, or `:auto` to take it from the file name.
        #
        # Default: nil, which reads and writes each value as text, as before.
        field :schema
        validate :schema_valid
        validate :schema_replaces_fields

        # Setting the schema builds the tabular again from it when it is next used, see #tabular.
        define_method(:schema=) do |value|
          @tabular = nil
          super(value)
        end

        # When `:format` is not supplied the file name can be used to infer the required format.
        # Optional.
        # Default: nil
        field :file_name, type: IOStreams::Path
      end

      module ClassMethods
        # Returns [Array<String>] the names of the deprecated options in the supplied properties of a category, with
        # String keys, that its schema replaces, see #schema: its `columns`. Overridden by the input category.
        def deprecated_column_options(properties)
          properties["columns"].present? ? ["columns"] : []
        end

        # Reports a deprecation warning, see RocketJob::Deprecation, for the deprecated options in the supplied
        # properties of a category, such as those that a job class defines it with, or that a Dirmon entry holds.
        def warn_deprecated_options(properties)
          properties = properties.to_h.stringify_keys
          names      = deprecated_column_options(properties)
          unless names.empty?
            options = names.collect { |name| "#{name}:" }.join(", ")
            RocketJob::Deprecation.warn(
              "#{options} #{names.size == 1 ? 'is' : 'are'} deprecated, describe the columns of the file with schema: " \
              "instead, see #{RocketJob::Deprecation::UPGRADE_GUIDE}"
            )
          end
          return if properties["format_options"].blank?

          RocketJob::Deprecation.warn(
            "format_options: is deprecated, use schema: instead, which gives the width of each field of a fixed width " \
            "file, see #{RocketJob::Deprecation::UPGRADE_GUIDE}"
          )
        end
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
        return @tabular ||= schema_tabular if schema.present?

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

      # Returns [Array<String>] the names of the deprecated options that this category sets, see
      # .deprecated_column_options, and `format_options`, whose schema #schema_proposal proposes.
      def deprecated_options_set
        names = self.class.deprecated_column_options(attributes.to_h.stringify_keys)
        names << "format_options" if format_options.present?
        names
      end

      private

      # Returns [Hash] the supplied deprecated options, by name, set to their defaults, as a schema proposal sets them,
      # see RocketJob::SchemaProposal#changes.
      def default_settings(names)
        names.to_h { |name| [name, self.class.fields[name].default_val] }
      end

      # Returns [Array] the schema of this category's fixed width layout, see #format_options, with String keys, as
      # MongoDB stores it, and nil, or nil and why IOStreams cannot translate the layout, such as two columns with one
      # key. The fields that the supplied columns leave out are skipped, which holds their place in each line.
      def layout_schema(keep = nil)
        layout = format_options.to_h.deep_symbolize_keys
        schema = JSON.parse(JSON.generate(IOStreams::Schema.from_layout(**layout)))
        if keep.present?
          keep = keep.map(&:to_s)
          schema["fields"] = schema["fields"].map do |field|
            keep.include?(field["name"].to_s) ? field : field.slice("name", "width", "start").merge("skip" => true)
          end
          # 7.0 keyed the records of a layout narrowed to its columns by Strings, whatever the keys of the layout.
          schema.delete("keyType")
        end
        [schema, nil]
      rescue IOStreams::Errors::InvalidLayout, ArgumentError => e
        [nil, "#{e.message} Write its schema by hand, see \"Moving a layout to a schema\" in IOStreams' upgrade guide"]
      end

      # Returns [IOStreams::Tabular] that reads or writes the records of this category by its schema, see #schema,
      # reading the file that holds it when it is a path or url.
      def schema_tabular
        IOStreams::Tabular.new(
          schema:    IOStreams::Schema::Source.new(schema).schema,
          format:    format == :auto ? nil : format,
          file_name: file_name
        )
      end

      # Returns [Array<Symbol>] the fields of this category that are set, which its schema replaces, see #schema.
      def fields_replaced_by_schema
        format_options.present? ? [:format_options] : []
      end

      # The fields that the schema replaces cannot be set with it, since IOStreams raises for them with a schema, rather
      # than apply one and ignore the other.
      def schema_replaces_fields
        return if schema.blank?

        errors.add(:schema, "needs a format, such as :csv, or :auto to take it from the file name") if format.blank?
        replaced = fields_replaced_by_schema
        errors.add(:schema, "replaces #{replaced.to_sentence}, which cannot be set with it") unless replaced.empty?
      end

      # Checks the schema without reading a file that holds it, since its store may not be available yet.
      def schema_valid
        case schema
        when nil
          nil
        when Hash
          IOStreams::Schema.new(schema)
        when String
          schema_path_valid
        else
          errors.add(:schema, "must be a Hash, or the path or url of a JSON file")
        end
      rescue ArgumentError => e
        errors.add(:schema, "is not valid: #{e.message}")
      end

      def schema_path_valid
        IOStreams.path(schema)
      rescue LoadError
        # A gem that the path needs is not installed in this process, so the path is checked when the job runs.
        nil
      rescue StandardError
        # The path is not included in the message, since a url can include credentials.
        errors.add(:schema, "is not a valid path or url")
      end
    end
  end
end

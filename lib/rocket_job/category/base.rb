require "active_support/concern"

module RocketJob
  module Category
    # Define the layout for each category of input or output data
    module Base
      extend ActiveSupport::Concern

      # The formats that a category accepts, see #format: `nil`, `:auto`, and the formats that IOStreams has when they
      # are listed, see `IOStreams.tabular_formats`, so that a format that an application registers after Rocket Job is
      # loaded is accepted. A list, such as of the choices in a form, enumerates them.
      class Formats
        include Enumerable

        def each(&)
          [nil, :auto].concat(IOStreams.tabular_formats).each(&)
        end
      end

      # The formats that a category accepts, see Formats.
      FORMATS = Formats.new.freeze

      included do
        field :name, type: ::Mongoid::StringifiedSymbol, default: :main

        # Whether to compress, encrypt, or use the bzip2 serialization for data in this category.
        field :serializer, type: ::Mongoid::StringifiedSymbol, default: :compress

        # The header columns when the file does not include a header row.
        # Note:
        # - All column names must be strings so that it can be serialized into MongoDB.
        # - Deprecated, use `schema`, whose fields are the columns, with `"header": false` for a file without a
        #   header row. It cannot be set with a schema, except on an input category, where it holds the header row
        #   read from the uploaded file, see RocketJob::Category::Input.
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
        validates_inclusion_of :format, in: FORMATS

        # The fields of the records in this category and the type of each one, as a Frictionless Table Schema, see
        # https://datapackage.org/standard/table-schema/, so that records are read as typed values, such as an Integer,
        # a BigDecimal or a Date, and written in the text form of each type, for every tabular format. It also gives
        # the position of each field of a fixed width file, with its `width`, and `"header": false` describes a file
        # without a header row. See `IOStreams::Schema`.
        #
        # A Hash, or the path or url of a JSON file that holds the schema, which is read when the category is first
        # used to read or write records.
        #
        # Example, for a fixed width file:
        #   {"fields" => [{"name" => "name", "type" => "string", "width" => 10},
        #                 {"name" => "zip", "type" => "integer", "width" => 5}]}
        #
        # Replaces `columns`, and on an input category `allowed_columns`, `required_columns`, `skip_unknown` and
        # `header_cleanser`, which are deprecated, and cannot be set with it.
        #
        # Default: nil, which reads and writes each value as text.
        field :schema
        validate :schema_valid
        validate :schema_replaces_fields

        # When `:format` is not supplied the file name can be used to infer the required format.
        # Optional.
        # Default: nil
        field :file_name, type: IOStreams::Path

        # The character encoding of the text in this category's files, such as "Windows-1252", "ISO-8859-1", or
        # "IBM037" for EBCDIC. Records are always UTF-8 within the job, since MongoDB only stores UTF-8, so an input
        # file is converted from this encoding when it is uploaded, and an output file is converted to it when it is
        # downloaded.
        #
        # An encoding set on the path supplied to `upload` or `download` is used instead, since that caller knows
        # how that file was written.
        #
        # Default: nil, which reads and writes UTF-8, or the format's own encoding, such as ASCII for fixed width.
        field :encoding, type: String
        validates_with EncodingValidator, attributes: [:encoding]

        after_initialize :rocketjob_format_options_migrate, unless: :new_record?

        # Setting a field that the tabular is built from builds it again when it is next used, see #tabular.
        %i[format file_name schema columns].each do |name|
          define_method(:"#{name}=") do |value|
            @tabular = nil
            super(value)
          end
        end
      end

      module ClassMethods
        # Returns [Hash] the supplied attributes or properties of a category to show to people, with its file name,
        # and the path or url of its schema, shown by its display name, without any credentials, see
        # RocketJob.path_display_name.
        def display_properties(properties)
          properties.to_h do |key, value|
            path = key.to_s == "file_name" || (key.to_s == "schema" && value.is_a?(String))
            [key, path ? RocketJob.path_display_name(value) : value]
          end
        end

        # Returns [Symbol] the name of the category that the supplied properties are for, see #merge_properties,
        # which is `:main` when they do not name one.
        def name_in(properties)
          (properties["name"] || properties[:name] || :main).to_s.to_sym
        end

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

      # Sets the supplied properties on this category, such as `{"encoding" => "Windows-1252"}`, as a Dirmon entry or
      # an UploadFileJob holds them for a job. Raises NoMethodError for a property that a category does not have.
      # Reports a deprecation warning for a deprecated option, see .warn_deprecated_options.
      def merge_properties(properties)
        self.class.warn_deprecated_options(attributes.slice("schema").merge(properties.to_h.stringify_keys))
        properties.each_pair { |key, value| public_send(:"#{key}=", value) }
        self
      end

      # Returns [Array<String>] why the supplied properties cannot be merged into this category, see
      # #merge_properties, such as a property that a category does not have, or a value that is not valid, such as
      # its encoding. Empty when they can. This category is not changed.
      def property_errors(properties)
        unknown = properties.keys.reject { |key| self.class.public_method_defined?(:"#{key}=") }
        return unknown.map { |key| "Unknown property: #{key}" } unless unknown.empty?

        category = deep_dup
        errors   = properties.filter_map do |key, value|
          category.public_send(:"#{key}=", value)
          nil
        rescue StandardError
          # The value is not included in the message, since it can be a secret, such as a url with credentials.
          "#{key.to_s.humanize} is not valid"
        end
        return errors unless errors.empty?

        category.valid? ? [] : category.errors.full_messages
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

      # Deprecated: use #schema, which gives the width of each field of a fixed width file.
      #
      # Sets the schema to that of the supplied fixed width layout, `layout:` and `truncate:`, as IOStreams translates
      # it, so that the format options that a Dirmon entry or an UploadFileJob holds still build the job.
      # Raises IOStreams::Errors::InvalidLayout when the layout is not valid.
      def format_options=(format_options)
        return if format_options.blank?

        schema = IOStreams.stream(StringIO.new).format_options(format_options.to_h.deep_symbolize_keys).schema
        # Stored with String keys and names, since MongoDB does not store Symbols.
        self.schema = JSON.parse(JSON.generate(schema))
      end

      # Returns [IOStreams::Tabular] that reads or writes the records of this category in its format, by its schema,
      # see #schema. It is built again after one of the fields that it is built from is set, such as #columns.
      def tabular
        @tabular ||= build_tabular
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

      private

      def build_tabular
        IOStreams::Tabular.new(format: tabular_format, file_name: file_name, **tabular_columns)
      end

      # Returns [Symbol] the format to read and write this category's files in, or nil to take it from the file name,
      # when its format is :auto.
      def tabular_format
        format == :auto ? nil : format
      end

      # Returns [Hash] the options of IOStreams::Tabular that describe the columns of this category's files: its
      # schema, see #schema, otherwise the deprecated fields that it replaces, when they are set.
      def tabular_columns
        return {schema: tabular_schema} if schema.present?

        {columns: columns.presence}.compact
      end

      # Returns [IOStreams::Schema] this category's schema, see #schema, reading its file when it is a path or url, or
      # nil when it has none.
      def tabular_schema
        IOStreams::Schema::Source.new(schema).schema if schema.present?
      end

      # Returns [Array<Symbol>] the deprecated fields of this category that are set, which its schema replaces, see
      # #schema.
      def fields_replaced_by_schema
        []
      end

      # The deprecated fields that the schema replaces cannot be set with it, since IOStreams rejects them with a
      # schema, rather than apply one and ignore the other.
      def schema_replaces_fields
        return if schema.blank?

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

      # Translates the `format_options` of a category saved before v8 into its schema, see #format_options=.
      def rocketjob_format_options_migrate
        return unless attributes.key?("format_options")

        # Kept when it cannot be translated, so that it is not lost when the job is saved.
        self.format_options = attributes["format_options"]
        remove_attribute(:format_options)
      rescue StandardError => e
        logger.warn("Could not translate the format_options of category #{name} into a schema", e)
      end

      # Sets this category's encoding on the supplied path, see #encoding, converting its text to and from the UTF-8
      # of the records, unless the caller already set an encoding on the path.
      def apply_encoding(path)
        return if encoding.blank? || path.setting(:encode)&.key?(:encoding)

        path.encoding("#{encoding}:UTF-8")
      end
    end
  end
end

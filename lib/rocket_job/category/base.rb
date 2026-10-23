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
        # Replaces the options that Rocket Job v8 removed, see .removed_option_names: `format_options`, the layout of a
        # fixed width file, the `columns` of a file without a header row, or of an output file, and on an input
        # category `allowed_columns`, `required_columns`, `skip_unknown` and `header_cleanser`.
        #
        # Default: nil, which reads and writes each value as text.
        field :schema
        validate :schema_valid

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

        # Setting a field that the tabular is built from builds it again when it is next used, see #tabular.
        %i[format file_name].each do |name|
          define_method(:"#{name}=") do |value|
            @tabular = nil
            super(value)
          end
        end

        # Setting the schema also reads it again, see #schema_descriptor.
        define_method(:schema=) do |value|
          @tabular           = nil
          @schema_descriptor = nil
          super(value)
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

        # Returns [Array<String>] the names of the options of this kind of category that Rocket Job v8 removed, since
        # its schema replaces them, see #schema, such as `format_options`, the layout of a fixed width file. Overridden
        # by the input and output categories.
        def removed_option_names
          %w[format_options]
        end

        # Returns [Array<String>] the names of the removed options, see .removed_option_names, that the supplied
        # properties of a category, with String or Symbol keys, set, such as the properties that a Dirmon entry holds, or
        # the attributes of a category that was saved before v8. One that is blank, or at its default, is left out, see
        # .removed_option_set?, since it had no effect.
        def removed_options(properties)
          properties = properties.to_h.stringify_keys
          removed_option_names.select { |name| removed_option_set?(name, properties[name]) }
        end

        # Returns [Hash] the supplied properties of a category, such as those that a job class defines it with, or that
        # a Dirmon entry holds, without the options that Rocket Job v8 removed, see .removed_option_names, which are only
        # left out when they are blank, or at their default, see .removed_options. An option that is still a field, such
        # as an input category's `columns`, is kept, since only some of its uses were removed.
        #
        # Raises ArgumentError, which names the removed options that are set, see .removed_options.
        def supported_properties(properties)
          removed = removed_options(properties)
          raise(ArgumentError, removed_options_message(removed)) unless removed.empty?

          left_out = removed_option_names - fields.keys
          properties.reject { |key, _| left_out.include?(key.to_s) }
        end

        # Returns [String] the message that says that the supplied options were removed, and what replaces them.
        def removed_options_message(names)
          "#{names.join(', ')} #{names.size == 1 ? 'was' : 'were'} removed in Rocket Job v8, describe the columns of " \
            "the file with the category's schema instead, see #{REMOVED_OPTIONS_GUIDE}"
        end

        private

        # Returns [true|false] whether the supplied value of the named removed option is set, rather than blank, or at
        # its default, which had no effect, see .removed_options. Overridden by the input category.
        def removed_option_set?(_name, value)
          value.present?
        end
      end

      # Where the upgrade guide says what replaces each option that Rocket Job v8 removed, see .removed_option_names.
      REMOVED_OPTIONS_GUIDE = "https://rocketjob.reidmorrison.com/upgrading.html#the-deprecated-category-options-are-removed".freeze

      # Sets the supplied properties on this category, such as `{"encoding" => "Windows-1252"}`, as a Dirmon entry or
      # an UploadFileJob holds them for a job. Raises NoMethodError for a property that a category does not have, and
      # ArgumentError for an option that Rocket Job v8 removed, see .supported_properties.
      def merge_properties(properties)
        self.class.supported_properties(properties).each_pair { |key, value| public_send(:"#{key}=", value) }
        self
      end

      # Returns [Array<String>] why the supplied properties cannot be merged into this category, see
      # #merge_properties, such as an option that Rocket Job v8 removed, a property that a category does not have, or a
      # value that is not valid, such as its encoding. Empty when they can. This category is not changed.
      def property_errors(properties)
        removed = self.class.removed_options(properties)
        return [self.class.removed_options_message(removed)] unless removed.empty?

        properties = self.class.supported_properties(properties)
        unknown    = properties.keys.reject { |key| self.class.public_method_defined?(:"#{key}=") }
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

      # Returns [IOStreams::Tabular] that reads or writes the records of this category in its format, by its schema,
      # see #schema. It is built again after one of the fields that it is built from is set, such as #format.
      def tabular
        @tabular ||= build_tabular
      end

      # Returns [RocketJob::Category::Input|RocketJob::Category::Output] a copy of this category, with its settings, for
      # the next run of its job, see RocketJob::Batch::Categories#rocket_job_restart_copy_to.
      def restart_copy
        clone
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
        check_removed_options
        IOStreams::Tabular.new(format: tabular_format, file_name: file_name, schema: tabular_schema)
      end

      # Raises ArgumentError when this category was saved before Rocket Job v8 with an option that v8 removed, which
      # IOStreams no longer reads, so that its records are not read or written as though it had none, see
      # .removed_options. Mongoid keeps such an option among the attributes of a saved category, but not as a field.
      def check_removed_options
        removed = self.class.removed_options(attributes.except(*self.class.fields.keys))
        return if removed.empty?

        raise(ArgumentError, "#{self.class.name.demodulize} category #{name}: #{self.class.removed_options_message(removed)}")
      end

      # Returns [Symbol] the format to read and write this category's files in, or nil to take it from the file name,
      # when its format is :auto.
      def tabular_format
        format == :auto ? nil : format
      end

      # Returns [IOStreams::Schema] this category's schema, see #schema, read once, see #schema_descriptor, or nil when
      # it has none.
      def tabular_schema
        IOStreams::Schema.new(schema_descriptor) if schema.present?
      end

      # Returns [Hash] this category's schema, see #schema, reading its file the first time when it is a path or url,
      # so that the tabular, and IOStreams for each slice of a file, see RocketJob::Category::Input#parse_records, use
      # it without reading the file again. Returns nil when it has none.
      def schema_descriptor
        return schema unless schema.is_a?(String)

        @schema_descriptor ||= read_schema_descriptor
      end

      # Returns [Hash] the schema in the JSON file at the path or url of #schema, checked as `IOStreams::Schema.read`
      # checks it, which returns the schema rather than the Hash that IOStreams reads each slice with. A UTF-8 byte
      # order mark at the start of the file is removed.
      #
      # Raises ArgumentError, which names the file without any credentials, when it is not JSON, or not a valid schema.
      def read_schema_descriptor
        descriptor = JSON.parse(IOStreams.path(schema).read.delete_prefix("\uFEFF"))
        IOStreams::Schema.new(descriptor)
        descriptor
      rescue JSON::ParserError, ArgumentError => e
        raise(ArgumentError, "Invalid schema in #{RocketJob.path_display_name(schema)}: #{e.message}")
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

      # Sets this category's encoding on the supplied path, see #encoding, converting its text to and from the UTF-8
      # of the records, unless the caller already set an encoding on the path.
      def apply_encoding(path)
        return if encoding.blank? || path.setting(:encode)&.key?(:encoding)

        path.encoding("#{encoding}:UTF-8")
      end
    end
  end
end

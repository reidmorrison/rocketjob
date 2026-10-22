module RocketJob
  module Category
    # Define the layout for each category of input or output data
    class Input
      include SemanticLogger::Loggable
      include Plugins::Document
      include Category::Base

      embedded_in :job, class_name: "RocketJob::Job", inverse_of: :input_categories

      # The fields that an upload sets, see #upload_state.
      UPLOAD_FIELDS = %w[file_name format].freeze
      private_constant :UPLOAD_FIELDS

      # The modes that a file can be uploaded in, see #mode.
      MODES = %i[line hash].freeze

      # Replaces each non-printable character, other than line endings, with a space.
      FIXED_WIDTH_CLEANER = ->(data, _replace) { data.gsub(/[^[:print:]\r\n]/, " ") }
      private_constant :FIXED_WIDTH_CLEANER

      # Slice size for this input collection
      field :slice_size, type: Integer, default: 100
      validates_presence_of :slice_size

      # The header row of a file that Rocket Job 7 uploaded in a tabular format without a schema, such as CSV, with each
      # column cleansed, such as `first_name` for the column `First Name`, which the workers read each of its lines by,
      # see #parse_record. Rocket Job v8 does not set them, since each slice of a file holds its header row instead, see
      # #copy_slices.
      #
      # Rocket Job v8 removed setting them for a file without a header row, see .removed_option_names, so an upload
      # raises while they are set, see #check_columns_not_set. Describe the columns of such a file with a schema with
      # `"header" => false` instead.
      field :columns, type: Array

      # How `#upload` reads a file, or the lines that its block writes:
      # :line
      #   Uploads the lines as they are, which the workers parse. This is the default behavior and is the most
      #   performant since it leaves the parsing of each line up to the workers themselves.
      # :hash
      #   In a tabular format, see #format, also parses each row as it is uploaded, so that a file with a row that
      #   cannot be read is rejected before any of it is processed. The slices still hold the lines, see #copy_slices.
      #   Without a format, uploads each row of a file as a Hash, read in the format of its file name.
      #   Not recommended for large files since the parsing is performed sequentially during the upload process.
      #
      # Use :hash when the entire file must be parsed/validated before processing is started, and upload time is not
      # important.
      #
      # Rocket Job v8 removed the :array mode, which uploaded each row as an Array, see .removed_option_names. A category
      # saved with it before v8 stays valid, so that the next run of a scheduled job is still created, and its upload
      # raises instead, see #upload_mode.
      field :mode, type: ::Mongoid::StringifiedSymbol, default: :line
      validates_inclusion_of :mode, in: [*MODES, :array]

      # What `#upload` does with each character of a file that is not valid in the file's encoding, see #encoding:
      #   :remove
      #     Removes it.
      #   :replace
      #     Replaces it with U+FFFD, the Unicode replacement character, so that it can be seen in the record.
      #   :raise
      #     Raises IOStreams::Errors::InvalidEncoding, which names the byte offset and line of the first one, and
      #     uploads nothing.
      #   nil
      #     The format's own: tabular formats, such as CSV, remove it, while fixed width files and lines raise.
      #
      # A `replace:` set on the path supplied to `#upload` is used instead.
      # Default: nil
      field :invalid_characters, type: ::Mongoid::StringifiedSymbol
      validates_inclusion_of :invalid_characters, in: [nil, :remove, :replace, :raise]

      validates_inclusion_of :serializer, in: %i[none compress encrypt]

      # Setting the columns builds the tabular again when it is next used, see #tabular.
      def columns=(value)
        @tabular = nil
        super
      end

      # Returns [Array<String>] the names of the options of an input category that Rocket Job v8 removed, see
      # Category::Base.removed_option_names: its column options, `allowed_columns`, `required_columns`, `skip_unknown`
      # and `header_cleanser`, the `columns` of a file without a header row, which an application can no longer set,
      # see #columns, and the :array `mode`, see #upload_mode.
      def self.removed_option_names
        super + %w[allowed_columns required_columns skip_unknown header_cleanser columns mode]
      end

      # Returns [String] the message that says that the supplied options were removed, see
      # Category::Base.removed_options_message, and for the :array `mode`, what to use instead.
      def self.removed_options_message(names)
        return super unless names.include?("mode")

        mode = "mode: :array was removed in Rocket Job v8, use :line, which the workers parse, or :hash to parse the " \
               "whole file when it is uploaded, see #{REMOVED_OPTIONS_GUIDE}"
        names == ["mode"] ? mode : "#{super(names - ['mode'])}. #{mode}"
      end

      # Returns [true|false] whether the supplied value of the named removed option is set, rather than blank, or at its
      # default, see Category::Base.removed_options: `skip_unknown` when true, `header_cleanser` when :none, and `mode`
      # when :array, otherwise when it is not blank.
      def self.removed_option_set?(name, value)
        case name
        when "skip_unknown"
          [true, "true"].include?(value)
        when "header_cleanser"
          value.to_s == "none"
        when "mode"
          value.to_s == "array"
        else
          super
        end
      end
      private_class_method :removed_option_set?

      # Yields each record of the supplied records of a slice of this category, as `#perform` receives it. The rows of a
      # file, see IOStreams::Slice, are read by IOStreams by the header row and format that they carry, with this
      # category's schema when it has one, see #schema. Otherwise each record is parsed on its own, see #parse. A blank
      # row is nil.
      #
      # A record that cannot be parsed raises before it is yielded, after the records before it, so that the caller
      # knows which record failed.
      #
      # Raises ArgumentError when this category was saved before Rocket Job v8 with an option that v8 removed, see
      # Category::Base#check_removed_options.
      def parse_records(records, &)
        return records.each { |record| yield parse(record) } unless records.is_a?(IOStreams::Slice)

        check_removed_options
        IOStreams.stream(records).schema(schema_descriptor).each(:hash, &)
      end

      # Returns the supplied record of a slice of this category as `#perform` receives it: parsed in this category's
      # format, see #parse_record, or as it is when the category has no format. A blank record of a tabular format is
      # nil.
      def parse(record)
        return record if record.nil? || !tabular?
        return if record.blank?

        parse_record(record)
      end

      # Returns [Hash|Array|String] the record uploaded into this category, parsed for `#perform`.
      #
      # A Hash was parsed when it was uploaded, for example by Rocket Job 7 in :hash mode, or by the application with
      # `upload_slice`, so it is kept as it is with a schema, otherwise only narrowed to the columns, when they are set.
      # A record of a category with a schema that is not a Hash, such as one that `upload_slice` uploaded, is read by
      # the schema, so it needs a format without a header row, such as JSON or fixed width, since the slices of a file
      # hold its header row instead, see #parse_records.
      def parse_record(record)
        if record.is_a?(Hash)
          return record if schema.present?

          return tabular.header.to_hash(record)
        end

        if tabular.header?
          raise(ArgumentError,
                "The tabular header columns _must_ be set before attempting to parse data that requires it.")
        end

        schema.present? ? tabular.record_parse(record) : tabular.read_record(record)
      end

      def data_store(job)
        RocketJob::Sliced::Input.new(
          collection_name: build_collection_name(:input, job),
          slice_class:     serializer_class,
          slice_size:      slice_size
        )
      end

      # Returns [IOStreams::Path] of file to upload.
      # Auto-detects file format from file name when format is :auto.
      def upload_path(stream = nil, original_file_name: nil)
        unless stream || file_name
          raise(ArgumentError, "Either supply a file name to upload, or set input_collection.file_name first")
        end

        path           = IOStreams.new(stream || file_name)
        path.file_name = original_file_name if original_file_name
        self.file_name = path.file_name

        detect_format(path)

        # Read the file in this category's encoding, unless the caller set one on the path, see #encoding.
        apply_encoding(path)

        # Read tabular input in its format, so that IOStreams reads it in the format's encoding, such as ASCII for
        # fixed width, and splits its lines where the format expects. An encoding set on the supplied path is kept,
        # since only the caller knows how the file was written.
        if tabular?
          path.format(format)
          # The fields of the records, and the position of each field of a fixed width file, so that IOStreams matches
          # the header row to the fields, and reads typed values in their columns, see #copy_slices. The schema is read
          # once, see #schema_descriptor, for the workers too, which read each slice with it, see #parse_records, so that
          # another schema cannot be set on the supplied path, also when this category has none.
          check_path_schema(path)
          path.schema(schema_descriptor) if schema.present?
          # Replace the non-printable characters of a fixed width file, such as NUL padding, so that the columns stay
          # in place, and remove those of any other tabular format.
          path.encoding(cleaner: format == :fixed ? FIXED_WIDTH_CLEANER : :printable)
        end
        apply_invalid_characters(path)
        path
      end

      # Returns [true|false] whether a file, or the lines that the block of an upload writes, is uploaded into this
      # category in slices of its rows, which carry the header row of their file and its format, see #copy_slices: when
      # it has a tabular format, see #tabular?, with or without a schema. Otherwise each record is uploaded as it is, see
      # #each_record, and passed to `#perform` as it is, see #parse.
      def slices?
        tabular?
      end

      # Writes the file that the supplied path reads, see #upload_path, to the supplied store of slices, see
      # Sliced::Writer::Input, in slices of up to `slice_size` rows, as IOStreams reads them, see
      # `IOStreams::Stream#each(:slice)`: after its header row, which IOStreams matches to the fields of the schema, when
      # there is one, so that a file whose columns do not match raises IOStreams::Errors::InvalidHeader before any
      # slice. Each slice carries the header row of its file, so that more than one file can be uploaded into this
      # category, and the workers read each row by it, see #parse_records.
      #
      # In the :hash mode, see #mode, IOStreams also parses each row before its slice is written, so that a file with a
      # value that is not valid raises before it is processed. Each slice still holds the rows as they are.
      #
      # Raises ArgumentError for any other options of the upload, such as `delimiter:`, which read the lines of a file
      # without a format, see #each_record, since the lines of this category's files are read in its format. Also
      # raises ArgumentError when this category cannot read a file, see #slice_target.
      def copy_slices(path, writer, mode: self.mode, **args)
        unless args.empty?
          raise(ArgumentError, "Input category #{name}: #{args.keys.map(&:inspect).join(', ')} cannot be supplied " \
                               "when uploading a file in the #{format.inspect} format, whose lines are read in it")
        end

        slice_target(writer).copy_from(path, mode: :line, validate: mode != :line)
      end

      # Yields to the supplied block of an upload, see RocketJob::Batch::IO#upload, the writer of the lines of a file,
      # such as its header row followed by its rows, which IOStreams writes to the supplied store of slices, see
      # Sliced::Writer::Input, as it reads the slices of a file, see #copy_slices: the header row is read from the first
      # lines, and matched to the fields of the schema, and each slice holds it. A format of :auto is replaced with that
      # of the file name of the upload, otherwise CSV, as for a file, see #upload_path.
      #
      # Raises ArgumentError for a record written to the writer that is not a line, such as a Hash, and when this
      # category cannot read the lines, see #slice_target.
      def write_slices(writer, &)
        detect_format(file_name)
        slice_target(writer).writer(:line, validate: mode != :line, &)
      end

      # Yields each record read from the supplied path in the supplied mode, see #mode, for a category without a format,
      # whose files are not uploaded in slices, see #slices?: each line, or in the :hash mode, each row of the file as a
      # Hash, read in the format of its file name.
      def each_record(path, mode: self.mode, **args, &)
        path.each(mode, **args, &)
      end

      # Returns [Symbol] the mode to upload a file in, see #mode: the supplied one, such as the `stream_mode` of an
      # upload, otherwise this category's.
      #
      # Raises ArgumentError for a mode other than :line or :hash, such as the :array mode, which Rocket Job v8 removed,
      # also when a category saved before v8 holds it.
      def upload_mode(mode = nil)
        mode = (mode || self.mode).to_sym
        return mode if MODES.include?(mode)

        message = "the upload mode must be :line or :hash, not #{mode.inspect}"
        message = self.class.removed_options_message(%w[mode]) if mode == :array
        raise(ArgumentError, "Input category #{name}: #{message}")
      end

      # Raises ArgumentError when this category cannot parse the records of the supplied kind of object, such as a query
      # or a range, which are values, or Arrays of them, rather than the lines of a file: in a format whose header row
      # is still to be read, such as CSV, see #parse_record, since only a file has a header row. Otherwise every slice
      # would fail once a worker parsed it.
      def check_record_upload(kind)
        return unless tabular? && tabular.header?

        raise(ArgumentError, "Input category #{name}: cannot upload #{kind} in the #{format.inspect} format, which " \
                             "reads the header row of a file. Upload it into a category without a format")
      end

      # Yields to upload a file into this category, see RocketJob::Batch::IO#upload. When the upload raises, its records
      # are not kept, so the fields that it set are restored, see #upload_state, such as the format that :auto was
      # replaced with, and the file can be uploaded again, such as when the job is retried.
      def uploading
        state = upload_state
        yield
      rescue Exception
        restore_upload_state(state)
        raise
      end

      # Returns [Hash] the fields that an upload sets, see #restore_upload_state: the file name, and the format that
      # :auto is replaced with.
      def upload_state
        UPLOAD_FIELDS.to_h { |name| [name, attributes[name]] }
      end

      # Sets the fields that an upload sets to the supplied ones, see #upload_state, so that the category is as it was
      # before the uploads since, whose records were removed.
      def restore_upload_state(state)
        UPLOAD_FIELDS.each { |name| public_send(:"#{name}=", state[name]) }
      end

      private

      # Replaces a format of :auto with the format of the supplied path, which its file name gives, otherwise CSV, so
      # that an upload reads its file, or the lines that its block writes, in it, see #upload_path and #write_slices.
      # Setting the format builds the tabular again.
      def detect_format(path)
        self.format = path&.format || :csv if format == :auto
      end

      # Returns [IOStreams::Stream] that writes lines to the supplied store of slices, see Sliced::Writer::Input, by this
      # category's schema, when it has one, in its format, which an upload has detected when it was :auto, see
      # #detect_format.
      #
      # Raises ArgumentError, before any line is read, when this category was saved before Rocket Job v8 with an option
      # that v8 removed, see Category::Base#check_removed_options, or, without a schema, holds columns that no upload
      # read, see #check_columns_not_set.
      def slice_target(writer)
        check_removed_options
        check_columns_not_set if schema.blank?
        IOStreams.stream(writer).schema(schema_descriptor).format(format)
      end

      # The text that replaces each character that is not valid in the file's encoding, see #invalid_characters.
      INVALID_CHARACTER_REPLACEMENTS = {remove: "", replace: "�"}.freeze
      private_constant :INVALID_CHARACTER_REPLACEMENTS

      # Raises ArgumentError when the supplied path has a schema other than this category's, which the workers read each
      # slice of the file with, see #parse_records, also when this category has none.
      def check_path_schema(path)
        return if path.schema.nil? || path.schema == schema

        raise(ArgumentError, "Set the schema of the file uploaded into input category #{name} on the category, not on " \
                             "the path, since its workers read each slice with the category's schema")
      end

      # Sets what the path does with each character that is not valid in the file's encoding, see
      # #invalid_characters, unless the caller set `replace:` on the path.
      def apply_invalid_characters(path)
        return if path.setting(:encode)&.key?(:replace)

        handling    = invalid_characters || (tabular? && format != :fixed ? :remove : :raise)
        replacement = INVALID_CHARACTER_REPLACEMENTS[handling]
        path.encoding(replace: replacement) if replacement
      end

      # Without a schema, the tabular reads the columns as the header row of a file that Rocket Job 7 uploaded, see
      # #columns, which it reads each of its lines by. With one, each slice of a file holds its header row instead, see
      # #parse_records.
      #
      # Raises ArgumentError when the columns are not the header row of a file, see #check_header_row.
      def build_tabular
        tabular = super
        return tabular if schema.present? || columns.blank?

        check_header_row(tabular)
        tabular
      end

      # Reads the columns as the header row of a file that Rocket Job 7 uploaded, see #columns, with the supplied
      # tabular, which cleanses each of them, as Rocket Job 7 cleansed them when the file was uploaded.
      #
      # Raises ArgumentError when reading them as a header row changes them, since Rocket Job v8 cannot read the lines
      # by them as Rocket Job 7 did: columns that were not cleansed, which an application set before v8 for a file
      # without a header row, see .removed_option_names.
      def check_header_row(tabular)
        tabular.read_header(columns)
        return if tabular.header.columns == columns

        raise(ArgumentError,
              "Input category #{name} holds columns that are not the header row of an uploaded file, so they are the " \
              "columns of a file without a header row: #{self.class.removed_options_message(%w[columns])}")
      end

      # Raises ArgumentError when the category holds columns, see #columns, before an upload into it without a schema
      # reads its file, which would read the first row of a file without a header row as its header row: the columns
      # of a scheduled job saved by Rocket Job 7, which copied the header row of an upload into its next run, or columns
      # set for a file without a header row, which Rocket Job v8 removed.
      def check_columns_not_set
        return if columns.blank?

        raise(ArgumentError,
              "Input category #{name} holds columns that no upload read from a file. Clear them when Rocket Job 7 " \
              "copied them from an earlier run of a scheduled job. Otherwise they are the columns of a file without a " \
              "header row: #{self.class.removed_options_message(%w[columns])}")
      end
    end
  end
end

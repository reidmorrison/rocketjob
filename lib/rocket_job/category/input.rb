module RocketJob
  module Category
    # Define the layout for each category of input or output data
    class Input
      include SemanticLogger::Loggable
      include Plugins::Document
      include Category::Base

      embedded_in :job, class_name: "RocketJob::Job", inverse_of: :input_categories

      autoload :UploadSlices, "rocket_job/category/input/upload_slices"
      autoload :WrittenLines, "rocket_job/category/input/written_lines"
      private_constant :UploadSlices, :WrittenLines

      # The fields that an upload sets, see #upload_state.
      UPLOAD_FIELDS = %w[file_name format columns header_uploaded].freeze
      private_constant :UPLOAD_FIELDS

      # The modes that a file can be uploaded in, see #mode.
      MODES = %i[line hash].freeze

      # Replaces each non-printable character, other than line endings, with a space.
      FIXED_WIDTH_CLEANER = ->(data, _replace) { data.gsub(/[^[:print:]\r\n]/, " ") }
      private_constant :FIXED_WIDTH_CLEANER

      # Slice size for this input collection
      field :slice_size, type: Integer, default: 100
      validates_presence_of :slice_size

      # The header row that an upload read from a file of a tabular format without a schema, such as CSV, with each
      # column cleansed, such as `first_name` for the column `First Name`, which the workers read each line by, see
      # #header_uploaded. With a schema, see #schema, each slice of an uploaded file holds its header row instead, see
      # #each_slice, so they are not set.
      #
      # Only an upload sets them: Rocket Job v8 removed setting them for a file without a header row, see
      # .removed_option_names. Describe its columns with a schema with `"header" => false` instead.
      field :columns, type: Array

      # When `#upload` is called with a file_name, it uploads the file using any of the following approaches:
      # :line
      #   Uploads the file a line (String) at a time for processing by workers.
      #   This is the default behavior and is the most performant since it leaves the parsing of each line
      #   up to the workers themselves.
      # :hash
      #   Parses each line from the file into a Hash and uploads each hash for processing by workers.
      #   The entire file is parsed before processing is started, so that a file with an invalid line is found first.
      #   Not recommended for large files since the CSV or other parsing is performed sequentially during the
      #   upload process. With a schema, see #schema, the lines are uploaded as they are, once each one is parsed.
      #
      # Use :hash when the entire file must be parsed/validated before processing is started, and upload time is not
      # important.
      # See IOStreams#each for more details.
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

      # Whether `columns` hold the header row that an upload read from its file, see #read_header. The category holds
      # the header row of one file, which the workers read each of its lines by, so another file with a header row
      # cannot be uploaded into it, see #extract_header_callback, and the next run of a restarted job reads the header
      # row of its own file, see #restart_copy.
      #
      # Default: false, which is also what a job saved before v8 reads, whose columns can be the header row of an
      # earlier run, or columns set for a file without a header row, which v8 removed, see #check_columns_not_set.
      field :header_uploaded, type: ::Mongoid::Boolean, default: false

      validates_inclusion_of :serializer, in: %i[none compress encrypt]

      # Setting the columns builds the tabular again when it is next used, see #tabular.
      def columns=(value)
        @tabular = nil
        super
      end

      # Returns [RocketJob::Category::Input] a copy of this category for the next run of its job, see
      # Category::Base#restart_copy, without the header row that an upload read from the file, see #header_uploaded, so
      # that the next run reads the header row of its own file.
      def restart_copy
        copy = super
        return copy unless header_uploaded?

        copy.columns         = nil
        copy.header_uploaded = false
        copy
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
      # category's schema, see #schema. Otherwise each record is parsed on its own, see #parse. A blank row is nil.
      #
      # A record that cannot be parsed raises before it is yielded, after the records before it, so that the caller
      # knows which record failed.
      def parse_records(records, &)
        return records.each { |record| yield parse(record) } unless records.is_a?(IOStreams::Slice)

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
      # A Hash was parsed when it was uploaded, for example in :hash mode without a schema, or by the application with
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

        # Auto detect the format based on the upload file name if present, which builds the tabular again.
        self.format = path.format || :csv if format == :auto

        # Read the file in this category's encoding, unless the caller set one on the path, see #encoding.
        apply_encoding(path)

        # Read tabular input in its format, so that IOStreams reads it in the format's encoding, such as ASCII for
        # fixed width, and splits its lines where the format expects. An encoding set on the supplied path is kept,
        # since only the caller knows how the file was written.
        if tabular?
          path.format(format)
          # The fields of the records, and the position of each field of a fixed width file, so that IOStreams matches
          # the header row to the fields, and reads typed values in their columns, see #each_slice and #each_record. The
          # schema is read once, see #schema_descriptor, for the workers too, which read each slice with it, see
          # #parse_records, so that another schema cannot be set on the supplied path. Without a schema, a schema set on
          # the supplied path is kept.
          if schema.present?
            check_path_schema(path)
            path.schema(schema_descriptor)
          end
          # Replace the non-printable characters of a fixed width file, such as NUL padding, so that the columns stay
          # in place, and remove those of any other tabular format.
          path.encoding(cleaner: format == :fixed ? FIXED_WIDTH_CLEANER : :printable)
        end
        apply_invalid_characters(path)
        path
      end

      # Returns [true|false] whether a file is uploaded into this category in slices of its rows, which carry the header
      # row of their file and its format, see #each_slice: when it has a schema, which describes the columns of its
      # files. Otherwise each record is uploaded on its own, see #each_record, and parsed by the columns that this
      # category holds, see #parse.
      def slices?
        tabular? && schema.present?
      end

      # Yields each slice of up to `slice_size` rows of the file that the supplied path reads, see #upload_path, as
      # IOStreams reads them, see `IOStreams::Stream#each(:slice)`: after its header row, which IOStreams matches to the
      # fields of the schema, so that a file whose columns do not match raises IOStreams::Errors::InvalidHeader before
      # any slice. Each slice carries the header row of its file, so that more than one file can be uploaded into this
      # category, and the workers read each row by it, see #parse_records.
      #
      # In the :hash mode, see #mode, IOStreams also parses each row as it reads it, so that a file with a value that is
      # not valid raises before it is processed. Each slice still holds the rows as they are.
      #
      # `on_first` is called with the header row, see UploadSlices.
      def each_slice(path, mode: self.mode, on_first: nil, **args, &)
        slices = UploadSlices.new(on_first, &)
        path.reader(:slice, size: slice_size, validate: mode != :line, **args) do |reader|
          reader.each { |slice| slices << slice }
          slices.finish(reader.header)
        end
      end

      # Yields a writer to the supplied block of an upload, see RocketJob::Batch::IO#upload, to which the block writes the
      # lines of a file, such as its header row followed by its rows, and yields each slice of them, as IOStreams reads
      # the slices of a file, see #each_slice and WrittenLines: the header row is read from the first lines, and matched
      # to the fields of the schema, and each slice holds it. `on_first` is called with the header row, see
      # UploadSlices.
      #
      # Raises ArgumentError for a record written to the writer that is not a line, such as a Hash.
      def each_written_slice(block, on_first: nil, &)
        slices = UploadSlices.new(on_first, &)
        WrittenLines.new(build_tabular, slices, size: slice_size, validate: mode != :line).write(block)
      end

      # Yields each record read from the supplied path in the supplied mode, see #mode.
      #
      # In :hash mode IOStreams reads the header row, since it is not yielded. In :line mode the header row is
      # yielded, and read by #extract_header_callback.
      def each_record(path, mode: self.mode, **args, &)
        path.each(mode, **args, &)
      end

      # Returns the lambda that the upload calls with each record before the first that it stores, instead of storing
      # it, until the lambda returns true, see `Sliced::Writer::Input`: it reads the header row, when the upload starts
      # with one, such as CSV, see `IOStreams::Tabular#header?`, then calls the supplied `on_first` with it. Otherwise
      # it calls `on_first` with the first record. Returns nil when there is neither. In :hash mode IOStreams reads the
      # header row itself, so `on_first` is not called for a file with one, as in v7, and every record is uploaded.
      #
      # A blank line before the header row is skipped, as IOStreams skips it when it reads the header row itself, such
      # as in :hash mode, so that the header row is not stored as a record. A category with a schema uploads slices
      # instead, see #each_slice.
      #
      # Raises ArgumentError when the category already holds the header row of a file, see #header_uploaded, since the
      # lines of another file could not be read by it, also in :hash mode, since its records would be narrowed to the
      # columns of that header row when they are parsed, see #parse_record.
      #
      # Raises ArgumentError when the category holds columns that an upload did not read, see #columns.
      def extract_header_callback(on_first, mode: self.mode)
        first_record = first_record_callback(on_first)
        return first_record unless tabular?

        if header_uploaded?
          raise(ArgumentError,
                "Input category #{name} already holds the header row of an uploaded file, which its lines are read " \
                "by. Upload each file with a header row into its own input category, or upload every file in the " \
                ":hash mode")
        end
        check_columns_not_set
        # IOStreams reads the header row itself in :hash mode, see #each_record.
        return tabular.header? ? nil : first_record if mode == :hash
        return first_record unless tabular.header?

        lambda do |row|
          next false if row.blank?

          read_header(row)
          self.header_uploaded = true
          # Call chained on_first if present
          on_first&.call(row)
          true
        end
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
      # are not kept, so the fields that it set are restored, see #upload_state, such as the columns that the header
      # row it read replaced, see #header_uploaded, and the file can be uploaded again, such as when the job is retried.
      def uploading
        state = upload_state
        yield
      rescue Exception
        restore_upload_state(state)
        raise
      end

      # Returns [Hash] the fields that an upload sets, see #restore_upload_state: the file name, the format that
      # :auto is replaced with, and the columns of the header row that it reads, see #header_uploaded.
      def upload_state
        UPLOAD_FIELDS.to_h { |name| [name, attributes[name]] }
      end

      # Sets the fields that an upload sets to the supplied ones, see #upload_state, so that the category is as it was
      # before the uploads since, whose records were removed.
      def restore_upload_state(state)
        UPLOAD_FIELDS.each { |name| public_send(:"#{name}=", state[name]) }
      end

      private

      # The text that replaces each character that is not valid in the file's encoding, see #invalid_characters.
      INVALID_CHARACTER_REPLACEMENTS = {remove: "", replace: "�"}.freeze
      private_constant :INVALID_CHARACTER_REPLACEMENTS

      # Raises ArgumentError when the supplied path has a schema other than this category's, which the workers read each
      # slice of the file with, see #parse_records.
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

      # Without a schema, the tabular reads the columns as the header row that an upload read from a file, see
      # #columns, which it reads each line by. With one, each slice of a file holds its header row instead, see
      # #parse_records.
      #
      # Raises ArgumentError when the columns are not the header row of a file, see #check_header_row.
      def build_tabular
        tabular = super
        return tabular if schema.present? || columns.blank?

        check_header_row(tabular)
        tabular
      end

      # Reads the columns as the header row that an upload read from a file, see #columns, with the supplied tabular,
      # which cleanses each of them, as it cleansed them when the file was uploaded.
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

      # Raises ArgumentError when the category holds columns that an upload did not read from a file, see #columns,
      # before an upload reads its file by them: the columns of a scheduled job saved by Rocket Job 7, which copied the
      # header row of an upload into its next run, or columns set for a file without a header row, which Rocket Job v8
      # removed.
      def check_columns_not_set
        return if columns.blank?

        raise(ArgumentError,
              "Input category #{name} holds columns that no upload read from a file. Clear them when Rocket Job 7 " \
              "copied them from an earlier run of a scheduled job. Otherwise they are the columns of a file without a " \
              "header row: #{self.class.removed_options_message(%w[columns])}")
      end

      # Returns the lambda that calls the supplied `on_first` with the first record uploaded, which is not stored, see
      # #extract_header_callback, or nil without one.
      def first_record_callback(on_first)
        return unless on_first

        lambda do |record|
          on_first.call(record)
          true
        end
      end

      # Reads the header row of a file into a category without a schema, cleansing each of its columns, see
      # `IOStreams::Tabular#read_header`, and keeps them as its columns, see #columns. A category with a schema uploads
      # slices instead, which hold the header row of their file, see #each_slice.
      def read_header(row)
        tabular.read_header(row)
        # Kept without building the tabular again, which has read them.
        self[:columns] = tabular.header.columns
      end
    end
  end
end

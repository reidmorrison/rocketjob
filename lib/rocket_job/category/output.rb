module RocketJob
  module Category
    # Define the layout for each category of input or output data
    class Output
      include SemanticLogger::Loggable
      include Plugins::Document
      include Category::Base

      embedded_in :job, class_name: "RocketJob::Job", inverse_of: :output_categories

      # Whether to skip nil values returned from the `perform` method.
      #   true: save nil values to the output categories.
      #   false: do not save nil values to the output categories.
      field :nils, type: ::Mongoid::Boolean, default: false

      validates_inclusion_of :serializer, in: %i[none compress encrypt bz2 encrypted_bz2 bzip2]

      # Returns [#<<] the writer of the results of `#perform` for one input slice, see Sliced::Writer::Output, which
      # writes each result as it is written, so that a result that cannot be written raises for the record that
      # returned it, and whose #records are the records to store once every result is written: without a format, the
      # results as they are, such as Strings or Hashes; otherwise the slice of the rows that IOStreams writes them as,
      # in this category's format, by its schema, see #schema, such as the lines of CSV after its header row, or [] for
      # no results. Each result is a Hash, keyed by the names of the fields, or an Array of the values of the fields
      # in order, as the first result that is not nil is.
      #
      # Raises ArgumentError when this category was saved before Rocket Job v8 with an option that v8 removed, see
      # Category::Base#check_removed_options, and, for the results of a retry, see Sliced::Writer::Output, that the
      # supplied records that an earlier attempt wrote are of another format, or, as the first result is written,
      # another header row, so that the retry fails at its first record, rather than once each record has run.
      def output_writer(append_to: nil)
        return ResultsWriter.new unless tabular?

        check_removed_options
        if append_to.is_a?(Array) && append_to.any?
          raise(ArgumentError, "Output category #{name}: cannot append rows in the #{output_format.inspect} format to " \
                               "the lines that Rocket Job 7 wrote, so retry the slice from its first record")
        end

        appended = append_to if append_to.is_a?(IOStreams::Slice)
        if appended && appended.format.to_s != output_format.to_s
          raise(ArgumentError, "Output category #{name}: cannot append rows in the #{output_format.inspect} format to " \
                               "the rows of the #{appended.format} format that an earlier attempt wrote")
        end

        store = OutputSlice.new(self, appended&.header)
        ResultsWriter.new(store, self) do |mode, &rows|
          IOStreams.stream(store).schema(schema_descriptor).format(output_format).writer(mode, &rows)
        end
      end

      # Returns [IOStreams::Slice|Array] the records to store for the supplied results, see #output_writer.
      def output_records(results)
        writer = output_writer
        results.each { |result| writer << result }
        writer.records
      end

      # Returns [Symbol] this category's format, or for :auto, the format of its file name, otherwise CSV.
      def output_format
        return format unless format == :auto

        (file_name && IOStreams.new(file_name).format) || :csv
      end

      # Returns [String] the header row of the file that this category's output is downloaded into, as IOStreams writes
      # it in its format, by its schema, such as "name,age" for CSV, or nil for a format without one, such as JSON,
      # and without a format.
      def header_line
        return unless tabular?

        io = StringIO.new
        IOStreams.stream(io).schema(schema_descriptor).format(output_format).writer(:slice) { |_slices| nil }
        io.string.chomp.presence
      end

      # Returns [IOStreams::Path] of the file to download into, in this category's encoding, see #encoding, and in
      # its format when it is tabular, so that IOStreams writes it in that format's encoding when this category has
      # none, such as ASCII for fixed width. An encoding set on the supplied path is kept.
      def download_path(stream = nil)
        path = IOStreams.new(stream || file_name)
        apply_encoding(path)
        path.format(output_format) if tabular?
        path
      end

      # Returns [String] the encoding of the text in this category's output file: its #encoding, or the format's own
      # when it has none, such as "US-ASCII" for fixed width, or nil for UTF-8.
      #
      # The slices of a binary serializer, such as `:bz2`, are written in it, since they are downloaded as they are,
      # where other slices are converted to it when they are downloaded, see #download_path.
      def text_encoding
        return encoding if encoding.present?

        tabular.encoding&.split(":")&.first if tabular?
      end

      def data_store(job)
        RocketJob::Sliced::Output.new(
          collection_name: build_collection_name(:output, job),
          slice_class:     serializer_class,
          # Asked for each slice, so that a change to the encoding or format of this category still applies.
          text_encoding:   -> { text_encoding }
        )
      end

      # Holds the one slice of the rows of the results of an input slice that IOStreams writes to it, see
      # #output_writer.
      class OutputSlice
        include IOStreams::Slice::Target

        attr_reader :slice

        # The supplied header row is that of the rows that an earlier attempt wrote, which a retry appends to.
        def initialize(category, header = nil)
          @category = category
          @header   = header
        end

        # One slice of every row of a write.
        def slice_size
          nil
        end

        # Raises ArgumentError for a header row that IOStreams takes from the first result, without a schema, since the
        # results of each slice could give another one, so that the columns of the file would differ from slice to slice.
        def write_header(header)
          @category.check_header_schema
          return if @header.nil? || @header == header

          raise(ArgumentError, "Output category #{@category.name}: cannot append rows of the header row " \
                               "#{header.inspect} to the rows of #{@header.inspect} that an earlier attempt wrote")
        end

        def write_slice(slice)
          @slice = slice
        end
      end
      private_constant :OutputSlice

      # Writes the results of `#perform` for one input slice, see #output_writer: as they are without a format,
      # otherwise to IOStreams in the mode of the first that is not nil, see FirstRecordWriter, after the nil results
      # before it, which the category keeps when it keeps nils.
      class ResultsWriter
        def initialize(store = nil, category = nil, &open)
          @store    = store
          @category = category
          @open     = open
          @results  = []
          @nils     = 0
          @size     = 0
        end

        # Returns [Integer] the number of results written.
        attr_reader :size

        # Writes the supplied result. Returns self, so that calls can be chained.
        def <<(result)
          if !@open
            @results << result
          elsif result.nil? && @writer.nil?
            @nils += 1
          else
            start(result) unless @writer
            check_kind(result)
            @writer << result
          end
          @size += 1
          self
        end

        # Keeps only the first supplied number of results, such as those written before a record whose results could
        # not all be written, see Sliced::Writer::Output, so that its retry does not write them again.
        def keep(size)
          @keep = size
        end

        # Returns [IOStreams::Slice|Array] the records to store, once every result is written.
        def records
          return @keep ? @results.first(@keep) : @results unless @open

          start(nil) if @writer.nil? && @nils.positive?
          @writer&.finish
          slice = @store.slice
          return [] unless slice
          return slice unless @keep && slice.size > @keep
          return [] if @keep.zero?

          slice.with_rows(slice.rows.first(@keep), record_number: 1)
        end

        private

        def start(result)
          @mode   = mode_of(result)
          @writer = FirstRecordWriter.new(mode: @mode, &@open)
          @nils.times { @writer << nil }
        end

        def mode_of(result)
          return :hash if result.nil? || result.is_a?(Hash)

          raise_kind(result) unless result.is_a?(Array)
          return :array if @category.schema.present?

          # Without a schema, IOStreams would read the first Array as the header row, rather than as a row.
          raise(ArgumentError, "Output category #{@category.name}: #perform returns Arrays of the values of the fields " \
                               "in order, so set a schema on the category, whose fields they are")
        end

        # Raises for a result of another kind than the first, see #mode_of.
        def check_kind(result)
          return if result.nil? || (@mode == :hash ? result.is_a?(Hash) : result.is_a?(Array))

          raise_kind(result)
        end

        def raise_kind(result)
          kind = "a Hash or an Array"
          kind = "#{@mode == :hash ? 'a Hash' : 'an Array'}, as the first result is," if @mode
          raise(ArgumentError, "Output category #{@category.name}: #perform must return #{kind} for the " \
                               "#{@category.output_format.inspect} format, not a #{result.class.name}")
        end
      end
      private_constant :ResultsWriter

      # Raises ArgumentError when this category has no schema, for a format that IOStreams writes a header row in,
      # see OutputSlice#write_header, so that the columns of its file are the fields of its schema.
      def check_header_schema
        return if schema.present?

        raise(ArgumentError, "Output category #{name}: the #{output_format.inspect} format writes a header row, so " \
                             "set a schema on the category, whose fields are the columns of the file")
      end

      # Returns [Array<String>] the names of the options of an output category that Rocket Job v8 removed, see
      # Category::Base.removed_option_names, and its `columns`, which named the columns of the file, since the header
      # row of output with a schema is the names of its fields, in order, see #schema.
      def self.removed_option_names
        super + %w[columns]
      end
    end
  end
end

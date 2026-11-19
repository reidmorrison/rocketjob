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

      # Returns [IOStreams::Slice|Array] the records to store for the supplied results of `#perform` of one input slice,
      # see Sliced::Writer::Output: without a format, the results as they are, such as Strings or Hashes; otherwise the
      # slice of the rows that IOStreams writes them as, in this category's format, by its schema, see #schema, such
      # as the lines of CSV after its header row, or [] for no results. The results are Hashes, keyed by the names of
      # the fields, or Arrays of the values of the fields in order.
      #
      # Raises ArgumentError for results that are neither all Hashes nor all Arrays, such as a String in a format whose
      # rows are values, and when this category was saved before Rocket Job v8 with an option that v8 removed, see
      # Category::Base#check_removed_options.
      def output_records(results)
        return results unless tabular?

        check_removed_options
        mode = [Hash, Array].find { |kind| results.all? { |result| result.nil? || result.is_a?(kind) } }
        unless mode
          other = results.find { |result| !result.nil? && !result.is_a?(Hash) && !result.is_a?(Array) }
          raise(ArgumentError, "Output category #{name}: #perform must return a Hash or an Array for the " \
                               "#{format.inspect} format, not a #{other.class.name}")
        end

        store = OutputSlice.new
        IOStreams.stream(store).schema(schema_descriptor).format(output_format).writer(mode.name.downcase.to_sym) do |rows|
          results.each { |result| rows << result }
        end
        store.slice || []
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
      # #output_records.
      class OutputSlice
        include IOStreams::Slice::Target

        attr_reader :slice

        # One slice of every row of a write.
        def slice_size
          nil
        end

        def write_slice(slice)
          @slice = slice
        end
      end
      private_constant :OutputSlice

      # Returns [Array<String>] the names of the options of an output category that Rocket Job v8 removed, see
      # Category::Base.removed_option_names, and its `columns`, which named the columns of the file, since the header
      # row of output with a schema is the names of its fields, in order, see #schema.
      def self.removed_option_names
        super + %w[columns]
      end

      private

      # Returns [Symbol] this category's format, or for :auto, the format of its file name, otherwise CSV.
      def output_format
        return format unless format == :auto

        (file_name && IOStreams.new(file_name).format) || :csv
      end
    end
  end
end

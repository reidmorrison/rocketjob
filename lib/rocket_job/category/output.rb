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

      # Returns [String] the supplied record, such as the Hash that `#perform` returned, rendered as a line in this
      # category's format, or the record as it is when this category has no format, see #tabular?.
      def render(record)
        tabular? ? tabular.render(record) : record
      end

      # Renders [String] the header line.
      # Returns [nil] if no header is needed.
      def render_header
        return if !tabular? || !tabular.requires_header?

        tabular.render_header
      end

      # Returns [IOStreams::Path] of the file to download into, in this category's encoding, see #encoding, and in
      # its format when it is tabular, so that IOStreams writes it in that format's encoding when this category has
      # none, such as ASCII for fixed width. An encoding set on the supplied path is kept.
      def download_path(stream = nil)
        path = IOStreams.new(stream || file_name)
        apply_encoding(path)
        path.format(tabular.format) if tabular?
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

      private

      # The header row of output with a schema is the names of its fields, in order, see #schema.
      def fields_replaced_by_schema
        columns.present? ? super << :columns : super
      end
    end
  end
end

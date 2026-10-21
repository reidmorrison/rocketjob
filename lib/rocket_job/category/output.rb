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

      # Renders [String] the header line.
      # Returns [nil] if no header is needed.
      def render_header
        return if !tabular? || !tabular.requires_header?

        tabular.render_header
      end

      def data_store(job)
        RocketJob::Sliced::Output.new(
          collection_name: build_collection_name(:output, job),
          slice_class:     serializer_class
        )
      end

      # Returns [RocketJob::SchemaProposal] the schema proposed to replace this category's deprecated options, its
      # `columns` or `format_options`, at the supplied place, such as "ImportJob, output category main", or nil when it
      # sets neither. The other keys of each record are skipped, as the columns skipped them. Changes nothing.
      def schema_proposal(where, defined: nil) # rubocop:disable Lint/UnusedMethodArgument
        names = deprecated_options_set
        return if names.empty?

        notes = [
          "A Time is written in ISO 8601, such as 2026-10-13T09:30:00.123456Z. Before, it was written without its " \
          "fraction, such as 2026-10-13 09:30:00 UTC, which a datetime field with \"format\" => " \
          "\"%Y-%m-%d %H:%M:%S UTC\" writes.",
          "A key of a result that only loosely matches a field, by its case or as a Symbol, is written. Before, its " \
          "column was left blank."
        ]
        if !tabular?
          notes = ["Without a format the category's results are not rendered, so its deprecated options had no effect, " \
                   "and are removed."]
        elsif format_options.present?
          schema, error = layout_schema
          if columns.present?
            notes << "Its columns named the values of an Array result, which a schema writes by the position of each " \
                     "field."
          end
        else
          schema = {"fieldsMatch" => "subset", "fields" => columns.map { |name| {"name" => name.to_s} }}
        end
        # A layout that cannot be translated keeps its settings until its schema is written by hand.
        changes = error ? {} : default_settings(names)
        changes["schema"] = schema if schema
        RocketJob::SchemaProposal.new(where: where, category: self, changes: changes, notes: notes, error: error)
      end

      private

      # The schema gives the columns of the file written, see Category::Base#schema.
      def fields_replaced_by_schema
        columns.present? ? super + [:columns] : super
      end
    end
  end
end

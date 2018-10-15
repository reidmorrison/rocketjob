module RocketJob
  module Batch
    # Format output results.
    #
    # Takes Batch::Results, Batch::Result, Hash, Array, or String and renders it for output.
    #
    # Example:
    #
    # tabular = Tabular.new(
    #   main:       IOStreams::Tabular.new(columns: main_file_headers, format: tabular_output_format),
    #   exceptions: IOStreams::Tabular.new(columns: exception_file_headers, format: tabular_output_format)
    # )
    #
    # tabular.render(row)
    class Tabular
      autoload :Input, 'rocket_job/batch/tabular/input'
      autoload :Output, 'rocket_job/batch/tabular/output'

      def initialize(map)
        @map = map
      end

      def tabular(category = :main)
        @map[category] || raise("No tabular map defined for category: #{category.inspect}")
      end

      # Iterate over responses and format using Tabular
      def render(row, category = :main)
        if row.is_a?(Batch::Results)
          results = Batch::Results.new
          row.each { |result| results << render(result) }
          results
        elsif row.is_a?(Batch::Result)
          row.value = tabular(row.category).render(row.value)
          row
        elsif row.blank?
          nil
        else
          tabular(category).render(row)
        end
      end

      def render_header(category = :main)
        tabular(category).render_header
      end

      def requires_header?(category = :main)
        tabular(category).requires_header?
      end

      def header?(category = :main)
        tabular(category).header?
      end
    end
  end
end

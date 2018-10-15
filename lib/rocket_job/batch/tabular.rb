module RocketJob
  module Batch
    # Format output results.
    #
    # Takes Sliced::CompositeResult, Sliced::Result, Hash, Array, or String and renders it for output.
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

      def tabular(category)
        @map[:main] || raise("No tabular map defined for category: #{category.inspect}")
      end

      # Iterate over responses and format using Tabular
      def render(row, category = :main)
        if row.is_a?(RocketJob::Sliced::CompositeResult)
          row.each { |result| result.value = render(result.value) }
          return row
        elsif row.is_a?(RocketJob::Sliced::Result)
          row.value = tabular(row.category).render(row.value)
          return row
        elsif row.blank?
          return
        end

        tabular(category).render(row)
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

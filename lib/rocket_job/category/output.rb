module RocketJob
  module Category
    # Define the layout for each category of input or output data
    class Output < Base
      # Renders [String] the header line.
      # Returns [nil] if no header is needed.
      def render_header
        return if !tabular? || !tabular.requires_header?

        tabular.render_header
      end
    end
  end
end

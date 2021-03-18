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
      field :nils, type: ::Mongoid::Boolean, default: true

      # Renders [String] the header line.
      # Returns [nil] if no header is needed.
      def render_header
        return if !tabular? || !tabular.requires_header?

        tabular.render_header
      end
    end
  end
end

module RocketJob
  module Categories
    # Custom Mongoid Type to hold input categories
    class Input < Base
      # return if tabular_input_header.blank? && tabular_input.header?
      # Render the row using tabular for each category
      # On Input only the :main category is used.
      def render(row)
        return if row.nil?

        category = main_category
        return row if category.nil? || !category.tabular?
        return nil if row.blank?

        tabular = category.tabular

        # Return the row as-is if the required header has not yet been set.
        if tabular.header?
          raise(ArgumentError,
                "The tabular header columns _must_ be set before attempting to parse data that requires it.")
        end

        tabular.record_parse(row)
      end

      def main_category
        @main_category ||= categories.find { |category| category.name == :main }
      end

      private

      def category_class
        Category::Input
      end
    end
  end
end

module RocketJob
  module Categories
    # Custom Mongoid Type to hold categories
    class Output < Base
      # Render the row using tabular for each category
      def render(row)
        return if row.nil?

        if row.is_a?(Batch::Result)
          category  = self[row.category]
          row.value = category.tabular.render(row.value) if category.tabular?
          return row
        end

        if row.is_a?(Batch::Results)
          results = Batch::Results.new
          row.each { |result| results << render(result) }
          return results
        end

        category = self[:main]
        return row unless category.tabular?
        return nil if row.blank?

        category.tabular.render(row)
      end

      private

      def category_class
        Category::Output
      end
    end
  end
end

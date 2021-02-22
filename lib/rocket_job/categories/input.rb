module RocketJob
  module Categories
    # Custom Mongoid Type to hold categories
    class Input < Base
      private

      def category_class
        Category::Input
      end
    end
  end
end

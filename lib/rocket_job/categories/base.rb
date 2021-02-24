module RocketJob
  module Categories
    # Custom Mongoid Type to hold categories
    class Base
      include Enumerable
      extend Forwardable

      def_delegators :@categories, :size, :each

      def initialize(categories = [:main])
        @categories = []
        add_categories(categories)
      end

      # Add one or more categories to the list of valid categories
      def <<(categories)
        add_categories(categories)
      end

      # Return the named category
      # Raises ArgumentError when the catgory is unknown
      def [](category_name)
        category_name = category_name.to_sym
        categories.find { |category| category.name == category_name } ||
          raise(ArgumentError, "Unknown Category: #{category_name.inspect}. Registered categories: #{names.join(',')}")
      end

      # Whether the named category is valid.
      def exist?(category_name)
        category_name = category_name.to_sym
        categories.any? { |category| category.name == category_name }
      end

      # Names of the registered categories.
      def names
        categories.collect(&:name)
      end

      # Converts an object of this instance into a database friendly value.
      def mongoize
        categories.collect(&:mongoize)
      end

      # Get the object as it was stored in the database, and instantiate
      # this custom class from it.
      def self.demongoize(object)
        new(object)
      end

      # Takes any possible object and converts it to how it would be
      # stored in the database.
      def self.mongoize(object)
        case object
        when Categories
          object.mongoize
        when Array
          new(object).mongoize
        when Hash
          new(object).mongoize
        else
          object
        end
      end

      # Converts the object that was supplied to a criteria and converts it
      # into a database friendly form.
      def self.evolve(object)
        case object
        when Categories
          object.mongoize
        else
          object
        end
      end

      private

      attr_reader :categories

      def category_class
        raise(NotImplementedError, "RocketJob::Category is an abstract base class")
      end

      def add_categories(categories)
        case categories
        when Hash
          categories.each_pair do |name, values|
            raise(ArgumentError, "Duplicate Category: #{name}") if exist?(name)

            @categories << category_class.new(name: name, **values)
          end
        else
          Array(categories).each do |category|
            category = build_category(category)
            raise(ArgumentError, "Duplicate Category: #{category.name}") if exist?(category.name)

            @categories << category
          end
        end
      end

      def build_category(category)
        case category
        when Hash
          category_class.new(**category.symbolize_keys)
        when Symbol
          category_class.new(name: category)
        when String
          category_class.new(name: category.to_sym)
        when category_class
          category
        when Category::Base
          raise(ArgumentError, "Invalid category class: #{category.inspect}")
        else
          raise(ArgumentError, "Unknown category: #{category.inspect}")
        end
      end
    end
  end
end

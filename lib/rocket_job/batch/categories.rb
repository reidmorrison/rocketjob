module RocketJob
  module Batch
    # Custom Mongoid Type to hold categories
    class Categories
      include Enumerable
      extend Forwardable

      def_delegators :@categories, :size, :each

      def initialize(categories = [:main])
        @categories = Array(categories).collect(&:to_sym)
      end

      # Add another category to the list of valid categories
      def <<(category)
        return unless valid?(category)

        @categories << category.to_sym
      end

      # Whether the named category is valid.
      def valid?(category)
        @categories.include?(category.to_sym)
      end

      def validate!(category)
        return true if valid?(category)

        raise(ArgumentError, "Category: #{category}, is not one of the registered categories: #{@categories.inspect}")
      end

      # Set the categories
      def ==(categories)
        case categories
        when Categories
          categories.categories.sort == @categories.sort
        when Array
          categories.collect(&:to_sym).sort == @categories.sort
        else
          categories == @categories
        end
      end

      def to_a(*args)
        @categories.dup
      end

      # Converts an object of this instance into a database friendly value.
      def mongoize
        categories.collect(&:to_s)
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
          object.collect(&:to_s)
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
    end
  end
end

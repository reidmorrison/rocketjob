require "active_support/concern"

module RocketJob
  module Batch
    module Categories
      extend ActiveSupport::Concern

      included do
        after_initialize :rocketjob_categories_assign, if: :new_record?
        after_initialize :rocketjob_categories_migrate, unless: :new_record?
        before_perform :rocketjob_categories_input_render
        after_perform :rocketjob_categories_output_render

        # List of categories that this job can load input data into
        embeds_many :input_categories, class_name: "RocketJob::Category::Input"

        # List of categories that this job can save output data into
        embeds_many :output_categories, class_name: "RocketJob::Category::Output"

        # Define a new input category
        # @see RocketJob::Category::Input
        def self.input_category(slice_size: nil, **args)
          self.slice_size = slice_size if slice_size
          category        = RocketJob::Category::Input.new(slice_size: slice_size, **args)
          if defined_input_categories.nil?
            self.defined_input_categories = [category]
          else
            rocketjob_categories_set(category, defined_input_categories)
          end
        end

        # Define a new output category
        # @see RocketJob::Category::Output
        def self.output_category(nils: nil, **args)
          self.collect_output     = true
          self.collect_nil_output = nils unless nils.nil?

          category = RocketJob::Category::Output.new(nils: nils, **args)
          if defined_output_categories.nil?
            self.defined_output_categories = [category]
          else
            rocketjob_categories_set(category, defined_output_categories)
          end
        end

        # Internal attributes
        class_attribute :defined_input_categories, instance_accessor: false, instance_predicate: false
        class_attribute :defined_output_categories, instance_accessor: false, instance_predicate: false

        private

        def self.rocketjob_categories_set(category, categories)
          index = categories.find_index { |cat| cat.name == category.name }
          index ? categories[index] = category : categories << category
          category
        end
      end

      def input_category(category_name = :main)
        category_name = category_name.to_sym
        category      = nil
        # .find does not work against this association
        input_categories.each { |catg| category = catg if catg.name == category_name }
        unless category
          raise(ArgumentError, "Unknown Input Category: #{category_name.inspect}. Registered categories: #{input_categories.collect(&:name).join(',')}")
        end
        category
      end

      def output_category(category_name = :main)
        category_name = category_name.to_sym
        category      = nil
        # .find does not work against this association
        output_categories.each { |catg| category = catg if catg.name == category_name }
        unless category
          raise(ArgumentError, "Unknown Output Category: #{category_name.inspect}. Registered categories: #{output_categories.collect(&:name).join(',')}")
        end
        category
      end

      private

      # def rocketjob_categories_assign
      #   self.input_categories =
      #     if self.class.defined_input_categories
      #       self.class.defined_input_categories.deep_dup
      #     else
      #       [RocketJob::Category::Input.new]
      #     end
      #
      #   self.output_categories =
      #     if self.class.defined_output_categories
      #       self.class.defined_output_categories.deep_dup
      #     else
      #       [RocketJob::Category::Output.new]
      #     end
      # end
      def rocketjob_categories_assign
        self.input_categories  = rocketjob_categories_assign_categories(
          input_categories,
          self.class.defined_input_categories,
          RocketJob::Category::Input
        )
        self.output_categories = rocketjob_categories_assign_categories(
          output_categories,
          self.class.defined_output_categories,
          RocketJob::Category::Output
        )
      end

      def rocketjob_categories_assign_categories(categories, defined_categories, category_class)
        defined_categories ? defined_categories.deep_dup : [category_class.new]
      end

      # Render the output from the perform.
      def rocketjob_categories_output_render
        return if @rocket_job_output.nil?

        # TODO: ..
        return unless output_categories
        return if output_categories.empty?

        @rocket_job_output = rocketjob_categories_output_render_row(@rocket_job_output)
      end

      # Parse the input data before passing to the perform method
      def rocketjob_categories_input_render
        return if @rocket_job_input.nil?

        @rocket_job_input = rocketjob_categories_input_render_row(@rocket_job_input)
      end

      def rocketjob_categories_input_render_row(row)
        return if row.nil?

        category = input_category
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

      def rocketjob_categories_output_render_row(row)
        return if row.nil?

        if row.is_a?(Batch::Result)
          category  = output_category(row.category)
          row.value = category.tabular.render(row.value) if category.tabular?
          return row
        end

        if row.is_a?(Batch::Results)
          results = Batch::Results.new
          row.each { |result| results << rocketjob_categories_output_render_row(result) }
          return results
        end

        category = output_category
        return row unless category.tabular?
        return nil if row.blank?

        category.tabular.render(row)
      end

      def rocketjob_categories_migrate
        unless self[:input_categories].blank? || !self[:input_categories].first.is_a?(Symbol)
          self[:input_categories] =
            self[:input_categories].collect { |category_name| RocketJob::Category::Input.new(name: category_name).as_document }
        end

        return if self[:output_categories].blank? || !self[:output_categories].first.is_a?(Symbol)

        self[:output_categories] =
          self[:output_categories].collect { |category_name| RocketJob::Category::Output.new(name: category_name).as_document }
      end
    end
  end
end

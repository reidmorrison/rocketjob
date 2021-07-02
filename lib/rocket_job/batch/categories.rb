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

        # Internal attributes
        class_attribute :defined_input_categories, instance_accessor: false, instance_predicate: false
        class_attribute :defined_output_categories, instance_accessor: false, instance_predicate: false

        # For RJMC to be able to edit jobs
        accepts_nested_attributes_for :input_categories, :output_categories
      end

      module ClassMethods
        # Define a new input category
        # @see RocketJob::Category::Input
        def input_category(**args)
          category = RocketJob::Category::Input.new(**args)
          if defined_input_categories.nil?
            self.defined_input_categories = [category]
          else
            rocketjob_categories_set(category, defined_input_categories)
          end
        end

        # Define a new output category
        # @see RocketJob::Category::Output
        def output_category(**args)
          category = RocketJob::Category::Output.new(**args)
          if defined_output_categories.nil?
            self.defined_output_categories = [category]
          else
            rocketjob_categories_set(category, defined_output_categories)
          end
        end

        # Builds this job instance from the supplied properties hash that may contain input and output categories.
        # Keeps the defaults and merges in settings without replacing existing categories.
        def from_properties(properties)
          return super(properties) unless properties.key?("input_categories") || properties.key?("output_categories")

          properties        = properties.dup
          input_categories  = properties.delete("input_categories")
          output_categories = properties.delete("output_categories")
          job               = super(properties)
          job.merge_input_categories(input_categories)
          job.merge_output_categories(output_categories)
          job
        end

        private

        def rocketjob_categories_set(category, categories)
          index = categories.find_index { |cat| cat.name == category.name }
          index ? categories[index] = category : categories << category
          category
        end
      end

      def input_category(category_name = :main)
        return category_name if category_name.is_a?(Category::Input)
        raise(ArgumentError, "Cannot supply Output Category to input category") if category_name.is_a?(Category::Output)

        category_name = category_name.to_sym
        # find does not work against this association
        input_categories.each { |category| return category if category.name == category_name }

        unless category_name == :main
          raise(
            ArgumentError,
            "Unknown Input Category: #{category_name.inspect}. Registered categories: #{input_categories.collect(&:name).join(',')}"
          )
        end

        # Auto-register main input category when not defined
        category = Category::Input.new(job: self)
        self.input_categories << category
        category
      end

      def output_category(category_name = :main)
        return category_name if category_name.is_a?(Category::Output)
        raise(ArgumentError, "Cannot supply Input Category to output category") if category_name.is_a?(Category::Input)

        category_name = category_name.to_sym
        # .find does not work against this association
        output_categories.each { |category| return category if category.name == category_name }

        raise(
          ArgumentError,
          "Unknown Output Category: #{category_name.inspect}. Registered categories: #{output_categories.collect(&:name).join(',')}"
        )
      end

      # Returns [true|false] whether the named category has already been defined
      def input_category?(category_name)
        category_name = category_name.to_sym
        # .find does not work against this association
        input_categories.each { |catg| return true if catg.name == category_name }
        false
      end

      def output_category?(category_name)
        category_name = category_name.to_sym
        # .find does not work against this association
        output_categories.each { |catg| return true if catg.name == category_name }
        false
      end

      def merge_input_categories(categories)
        return if categories.blank?

        categories.each do |properties|
          category_name = (properties["name"] || properties[:name] || :main).to_sym
          category      = input_category(category_name)
          properties.each { |key, value| category.public_send("#{key}=".to_sym, value) }
        end
      end

      def merge_output_categories(categories)
        return if categories.blank?

        categories.each do |properties|
          category_name = (properties["name"] || properties[:name] || :main).to_sym
          category      = output_category(category_name)
          properties.each { |key, value| category.public_send("#{key}=".to_sym, value) }
        end
      end

      private

      def rocketjob_categories_assign
        # Input categories defaults to :main if none was set in the class
        if input_categories.empty?
          self.input_categories =
            if self.class.defined_input_categories
              self.class.defined_input_categories.deep_dup
            else
              [RocketJob::Category::Input.new]
            end
        end

        return if !self.class.defined_output_categories || !output_categories.empty?

        # Input categories defaults to nil if none was set in the class
        self.output_categories = self.class.defined_output_categories.deep_dup
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

      # Migrate existing v5 batch jobs to v6
      def rocketjob_categories_migrate
        return unless attribute_present?(:input_categories) && self[:input_categories]&.first.is_a?(Symbol)

        serializer = :none
        if attribute_present?(:compress)
          serializer = :compress if self[:compress]
          remove_attribute(:compress)
        end

        if attribute_present?(:encrypt)
          serializer = :encrypt if self[:encrypt]
          remove_attribute(:encrypt)
        end

        slice_size = 100
        if attribute_present?(:slice_size)
          slice_size = self[:slice_size].to_i
          remove_attribute(:slice_size)
        end

        main_input_format  = nil
        main_input_mode    = :line
        main_input_columns = nil
        # Only migrate tabular attributes if the job also removed the tabular plugin.
        unless respond_to?(:tabular_input_render)
          if attribute_present?(:tabular_input_format)
            main_input_format = self[:tabular_input_format]
            remove_attribute(:tabular_input_format)
          end

          if attribute_present?(:tabular_input_mode)
            main_input_mode = self[:tabular_input_mode]
            remove_attribute(:tabular_input_mode)
          end

          if attribute_present?(:tabular_input_header)
            main_input_columns = self[:tabular_input_header]
            remove_attribute(:tabular_input_header)
          end
        end

        file_name = nil
        if attribute_present?(:upload_file_name)
          file_name = self[:upload_file_name]
          remove_attribute(:upload_file_name)
        end

        existing                = self[:input_categories]
        self[:input_categories] = []
        self[:input_categories] = existing.collect do |category_name|
          RocketJob::Category::Input.new(
            name:       category_name,
            file_name:  file_name,
            serializer: serializer,
            slice_size: slice_size,
            format:     [:main, "main"].include?(category_name) ? main_input_format : nil,
            columns:    [:main, "main"].include?(category_name) ? main_input_columns : nil,
            mode:       [:main, "main"].include?(category_name) ? main_input_mode : nil
          ).as_document
        end

        collect_output = false
        if attribute_present?(:collect_output)
          collect_output = self[:collect_output]
          remove_attribute(:collect_output)
        end

        collect_nil_output = true
        if attribute_present?(:collect_nil_output)
          collect_nil_output = self[:collect_nil_output]
          remove_attribute(:collect_nil_output)
        end

        main_output_format  = nil
        main_output_columns = nil
        main_output_options = nil

        # Only migrate tabular attributes if the job also removed the tabular plugin.
        unless respond_to?(:tabular_output_render)
          if attribute_present?(:tabular_output_format)
            main_output_format = self[:tabular_output_format]
            remove_attribute(:tabular_output_format)
          end

          if attribute_present?(:tabular_output_header)
            main_output_columns = self[:tabular_output_header]
            remove_attribute(:tabular_output_header)
          end

          if attribute_present?(:tabular_output_options)
            main_output_options = self[:tabular_output_options]
            remove_attribute(:tabular_output_options)
          end
        end

        existing                 = self[:output_categories]
        self[:output_categories] = []
        if collect_output
          if existing.blank?
            self[:output_categories] = [
              RocketJob::Category::Output.new(
                nils:           collect_nil_output,
                format:         main_output_format,
                columns:        main_output_columns,
                format_options: main_output_options
              ).as_document
            ]
          elsif existing.first.is_a?(Symbol)
            self[:output_categories] = existing.collect do |category_name|
              RocketJob::Category::Output.new(
                name:           category_name,
                serializer:     serializer,
                nils:           collect_nil_output,
                format:         [:main, "main"].include?(category_name) ? main_output_format : nil,
                columns:        [:main, "main"].include?(category_name) ? main_output_columns : nil,
                format_options: [:main, "main"].include?(category_name) ? main_output_options : nil
              ).as_document
            end
          end
        end
      end
    end
  end
end

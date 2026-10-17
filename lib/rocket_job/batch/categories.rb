require "active_support/concern"

module RocketJob
  module Batch
    module Categories
      extend ActiveSupport::Concern

      # The v5 `tabular_input_mode` values, and the input category `mode` that replaced each one.
      V5_INPUT_MODES = {"row" => :array, "record" => :hash}.freeze

      # The properties that hold the settings of the job's categories, and the class of each one's categories.
      CATEGORY_PROPERTIES = {
        input_categories:  RocketJob::Category::Input,
        output_categories: RocketJob::Category::Output
      }.freeze

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
        # Define a new input category, or replace the input category with the same name.
        # A subclass that defines a category does not change the categories of its parent class.
        # @see RocketJob::Category::Input
        def input_category(**args)
          category                      = RocketJob::Category::Input.new(**args)
          self.defined_input_categories = rocketjob_categories_with(defined_input_categories, category)
          category
        end

        # Define a new output category, or replace the output category with the same name.
        # A subclass that defines a category does not change the categories of its parent class.
        # @see RocketJob::Category::Output
        def output_category(**args)
          category                       = RocketJob::Category::Output.new(**args)
          self.defined_output_categories = rocketjob_categories_with(defined_output_categories, category)
          category
        end

        # Builds this job instance from the supplied properties hash that may contain input and output categories.
        # Keeps the defaults and merges in settings without replacing existing categories.
        # The keys can be Strings or Symbols, since Mongoid 9 returns Hash field keys as Strings, earlier versions as
        # Symbols.
        def from_properties(properties)
          properties = properties.stringify_keys
          return super unless properties.key?("input_categories") || properties.key?("output_categories")

          input_categories  = properties.delete("input_categories")
          output_categories = properties.delete("output_categories")
          job               = super
          job.merge_input_categories(input_categories)
          job.merge_output_categories(output_categories)
          job
        end

        # Returns [Array<String>] why the supplied properties cannot build this job, see
        # RocketJob::Plugins::Job::Model.property_errors, also asking each category of the job whether its properties
        # can be merged into it, see `from_properties`, naming the category in each error, such as
        # "Input category main: Encoding ...". The job is not built.
        def property_errors(properties)
          category_properties = properties.select { |key, _| CATEGORY_PROPERTIES.key?(key.to_sym) }
          errors              = super(properties.except(*category_properties.keys))

          category_properties.each_pair do |key, categories|
            errors.concat(rocketjob_category_property_errors(key.to_sym, categories))
          end
          errors
        end

        # Returns [Array<RocketJob::Category::Input|RocketJob::Category::Output>] new copies of the categories that a
        # new job of this class starts with, for the supplied property, `:input_categories` or `:output_categories`.
        # The input categories are `main` when the class does not define any.
        def rocketjob_new_categories(key)
          if key == :input_categories
            defined_input_categories ? defined_input_categories.deep_dup : [RocketJob::Category::Input.new]
          else
            defined_output_categories ? defined_output_categories.deep_dup : []
          end
        end

        # Returns [Hash] the supplied attributes or properties of this job class to show to people, see
        # RocketJob::Plugins::Job::Model.display_properties, with each of its input and output categories also
        # showing its file name without any credentials.
        def display_properties(properties)
          super.to_h do |key, value|
            category_class = CATEGORY_PROPERTIES[key.to_sym]
            next [key, value] unless category_class && value.is_a?(Array)

            [key, value.map { |category| category.is_a?(Hash) ? category_class.display_properties(category) : category }]
          end
        end

        private

        # Returns [Array] a copy of the supplied categories, which can be nil, with the supplied category in place of
        # the one with the same name, or after them. The supplied categories are not changed, since a class shares
        # them with its subclasses.
        def rocketjob_categories_with(categories, category)
          categories = categories ? categories.dup : []
          index      = categories.find_index { |cat| cat.name == category.name }
          index ? categories[index] = category : categories << category
          categories
        end

        # Returns [Array<String>] why the supplied list of the properties of each category cannot be merged into the
        # categories that a new job starts with, see `from_properties`, such as a category that it does not define.
        def rocketjob_category_property_errors(key, categories)
          unless categories.is_a?(Array) && categories.all?(Hash)
            return ["#{key} must be a list of the properties of each category, such as " \
                    "[{\"name\" => \"main\", \"encoding\" => \"Windows-1252\"}]"]
          end

          category_class = CATEGORY_PROPERTIES[key]
          direction      = category_class.name.demodulize
          defaults       = rocketjob_new_categories(key)
          categories.flat_map do |properties|
            name     = category_class.name_in(properties)
            category = defaults.find { |default| default.name == name }
            unless category
              next ["#{direction} category #{name}: Not defined by the job #{self.name}, which defines: " \
                    "#{defaults.empty? ? 'none' : defaults.collect(&:name).join(', ')}"]
            end

            category.property_errors(properties).map { |message| "#{direction} category #{name}: #{message}" }
          end
        end
      end

      def input_category(category_name = :main)
        return category_name if category_name.is_a?(Category::Input)
        raise(ArgumentError, "Cannot supply Output Category to input category") if category_name.is_a?(Category::Output)

        # Initialize categories when this method is called before initialization is complete
        rocketjob_categories_assign if input_categories.empty?

        rocketjob_category_named(input_categories, category_name) ||
          raise(
            ArgumentError,
            "Unknown Input Category: #{category_name.to_sym.inspect}. Registered categories: #{input_categories.collect(&:name).join(',')}"
          )
      end

      def output_category(category_name = :main)
        return category_name if category_name.is_a?(Category::Output)
        raise(ArgumentError, "Cannot supply Input Category to output category") if category_name.is_a?(Category::Input)

        # Initialize categories when this method is called before initialization is complete
        rocketjob_categories_assign if output_categories.empty? && self.class.defined_output_categories

        rocketjob_category_named(output_categories, category_name) ||
          raise(
            ArgumentError,
            "Unknown Output Category: #{category_name.to_sym.inspect}. Registered categories: #{output_categories.collect(&:name).join(',')}"
          )
      end

      # Returns [true|false] whether the named category has already been defined
      def input_category?(category_name)
        !rocketjob_category_named(input_categories, category_name).nil?
      end

      def output_category?(category_name)
        !rocketjob_category_named(output_categories, category_name).nil?
      end

      def merge_input_categories(categories)
        return if categories.blank?

        categories.each do |properties|
          input_category(RocketJob::Category::Input.name_in(properties)).merge_properties(properties)
        end
      end

      def merge_output_categories(categories)
        return if categories.blank?

        categories.each do |properties|
          output_category(RocketJob::Category::Output.name_in(properties)).merge_properties(properties)
        end
      end

      private

      # Keeps the input and output categories of this job, with their settings, such as `slice_size`, when it restarts,
      # see RocketJob::Plugins::Job::Persistence#create_restart!.
      def rocket_job_restart_copy_to(job)
        super
        job.input_categories  = input_categories
        job.output_categories = output_categories
      end

      # Returns [RocketJob::Category::Input|RocketJob::Category::Output] the category with the supplied name, or nil.
      def rocketjob_category_named(categories, category_name)
        category_name = category_name.to_sym
        # .find does not work against this association
        categories.each { |category| return category if category.name == category_name }
        nil
      end

      def rocketjob_categories_assign
        self.input_categories = self.class.rocketjob_new_categories(:input_categories) if input_categories.empty?
        return unless output_categories.empty?

        categories             = self.class.rocketjob_new_categories(:output_categories)
        self.output_categories = categories unless categories.empty?
      end

      # Render the output from the perform.
      def rocketjob_categories_output_render
        return if @rocket_job_output.nil? || output_categories.empty?

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
        return row unless category.tabular?
        return nil if row.blank?

        category.parse_record(row)
      end

      def rocketjob_categories_output_render_row(row)
        return if row.nil?

        if row.is_a?(Batch::Result)
          row.value = output_category(row.category).render(row.value)
          return row
        end

        if row.is_a?(Batch::Results)
          results = Batch::Results.new
          row.each { |result| results << rocketjob_categories_output_render_row(result) }
          return results
        end

        category = output_category
        return nil if row.blank? && category.tabular?

        category.render(row)
      end

      # Migrate existing v5 batch jobs to v6
      def rocketjob_categories_migrate
        return unless attributes["input_categories"]&.first.is_a?(Symbol)

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
        if attribute_present?(:tabular_input_format)
          main_input_format = self[:tabular_input_format]
          remove_attribute(:tabular_input_format)
        end

        if attribute_present?(:tabular_input_mode)
          main_input_mode = V5_INPUT_MODES.fetch(self[:tabular_input_mode].to_s, self[:tabular_input_mode])
          remove_attribute(:tabular_input_mode)
        end

        if attribute_present?(:tabular_input_header)
          main_input_columns = self[:tabular_input_header]
          remove_attribute(:tabular_input_header)
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

        existing                 = self[:output_categories]
        self[:output_categories] = []
        return unless collect_output

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

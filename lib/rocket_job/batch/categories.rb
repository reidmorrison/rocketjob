require "active_support/concern"

module RocketJob
  module Batch
    module Categories
      extend ActiveSupport::Concern

      included do
        before_perform :rocketjob_categories_input_render
        after_perform :rocketjob_categories_output_render

        # Optional Array<Symbol> list of categories that this job can output to
        #
        # By using categories the output from #perform can be placed in different
        # output collections, and therefore different output files
        #
        # Categories must be declared in advance to avoid a #perform method
        # accidentally writing its results to an unknown category
        field :output_categories, type: RocketJob::Categories::Output, default: [:main], class_attribute: true

        # Optional Array<Symbol> list of categories that this job can load input data into
        field :input_categories, type: RocketJob::Categories::Input, default: [:main], class_attribute: true

        def self.input_category(slice_size: nil, **args)
          categories = input_categories
          categories = RocketJob::Categories::Input.new(categories) unless categories.is_a?(RocketJob::Categories::Input)
          categories.replace(RocketJob::Category::Input.new(**args))
          self.slice_size       = slice_size if slice_size
          self.input_categories = categories.mongoize
        end

        def self.output_category(name: :main, nils: nil, **args)
          categories = output_categories
          categories = RocketJob::Categories::Output.new(categories) unless categories.is_a?(RocketJob::Categories::Output)
          categories.replace(RocketJob::Category::Output.new(name: name, **args))
          self.collect_output     = true
          self.collect_nil_output = nils unless nils.nil?
          self.output_categories  = categories.mongoize
        end
      end

      # Cache input categories.
      def input_categories
        @input_categories ||= super
      end

      # Cache output categories.
      def output_categories
        @output_categories ||= super
      end

      # Cache input categories.
      def input_categories=(input_categories)
        if input_categories.is_a?(RocketJob::Categories::Input)
          @input_categories = input_categories
          super(input_categories.mongoize)
        else
          @input_categories = nil
          super(input_categories)
        end
      end

      # Cache output categories.
      def output_categories=(output_categories)
        if output_categories.is_a?(RocketJob::Categories::Output)
          @output_categories = output_categories
          super(output_categories.mongoize)
        else
          @output_categories = nil
          super(output_categories)
        end
      end

      private

      # Render the output from the perform.
      def rocketjob_categories_output_render
        return unless collect_output?

        @rocket_job_output = output_categories.render(@rocket_job_output)
      end

      # Parse the input data before passing to the perform method
      def rocketjob_categories_input_render
        @rocket_job_input = input_categories.render(@rocket_job_input)
      end
    end
  end
end

require 'active_support/concern'

module RocketJob
  module Batch
    module Tabular
      # For the simple case where all `output_categories` have the same format,
      # If multiple output categories are used with different formats, then use IOStreams::Tabular directly
      # instead of this plugin.
      module Output
        extend ActiveSupport::Concern

        included do
          field :tabular_output_header, type: Array, class_attribute: true, user_editable: true, copy_on_restart: true
          field :tabular_output_format, type: Symbol, default: :csv, class_attribute: true, user_editable: true, copy_on_restart: true

          validates_inclusion_of :tabular_output_format, in: IOStreams::Tabular.registered_formats

          after_perform :tabular_output_render
        end

        def tabular_output_header=(tabular_output_header)
          super(tabular_output_header)
          @tabular_output = nil
        end

        def tabular_output_format=(tabular_output_format)
          super(tabular_output_format)
          @tabular_output = nil
        end

        private

        # Delimited instance used for this slice, by a single worker (thread)
        def tabular_output
          @tabular_output ||= IOStreams::Tabular.new(columns: tabular_output_header, format: tabular_output_format)
        end

        # Render the output from the perform.
        def tabular_output_render
          @rocket_job_output = tabular_output.render(@rocket_job_output)
        end

        # Write the tabular_output_header to the output in its own slice
        def tabular_output_write_header
          return unless tabular_output_header.present? && tabular_output.render_header?

          # Add the header output slice with just the header in it and
          # id of 0 to make it the first record in the output
          slice = output.new(id: 0)
          slice << tabular_output.render(tabular_output_header)
          slice.save!
        end

      end
    end
  end
end

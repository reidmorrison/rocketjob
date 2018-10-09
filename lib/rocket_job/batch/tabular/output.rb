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

          before_batch :tabular_output_default_header if respond_to?(:tabular_input_header)
          after_perform :tabular_output_render
        end

        # Clear out cached tabular_output any time header or format is changed.
        def tabular_output_header=(tabular_output_header)
          super(tabular_output_header)
          @tabular_output = nil
        end

        def tabular_output_format=(tabular_output_format)
          super(tabular_output_format)
          @tabular_output = nil
        end

        # Overrides: `RocketJob::Batch::IO#download` to add the `tabular_output_header`.
        def download(file_name_or_io = nil, **args, &block)
          # No header required
          return super(file_name_or_io, **args, &block) unless tabular_output.render_header?

          if tabular_output_header.blank?
            raise(ArgumentError, "tabular_output_header must be set before calling #download when tabular_output_format is #{tabular_output_format}")
          end

          header = tabular_output.render(tabular_output_header)
          super(file_name_or_io, header_line: header, **args, &block)
        end

        private

        # Delimited instance used for this slice, by a single worker (thread)
        def tabular_output
          @tabular_output ||= IOStreams::Tabular.new(columns: tabular_output_header, format: tabular_output_format)
        end

        # Render the output from the perform.
        def tabular_output_render
          @rocket_job_output = tabular_output.render(@rocket_job_output) if collect_output?
        end

        private

        # Set the output header to the input header if no output header is present
        def tabular_output_default_header
          self.tabular_output_header ||= tabular_input_header
        end
      end
    end
  end
end

require "active_support/concern"

module RocketJob
  module Batch
    class Tabular
      # For the simple case where all `output_categories` have the same format,
      # If multiple output categories are used with different formats, then use IOStreams::Tabular directly
      # instead of this plugin.
      module Output
        extend ActiveSupport::Concern

        included do
          field :tabular_output_header, type: Array, class_attribute: true, user_editable: true, copy_on_restart: true
          field :tabular_output_format, type: Mongoid::StringifiedSymbol, default: :csv, class_attribute: true, user_editable: true, copy_on_restart: true
          field :tabular_output_options, type: Hash, class_attribute: true

          validates_inclusion_of :tabular_output_format, in: IOStreams::Tabular.registered_formats

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
        def download(file_name_or_io = nil, category: :main, **args, &block)
          unless tabular_output.requires_header?(category)
            return super(file_name_or_io, category: category, **args, &block)
          end

          header = tabular_output.render_header(category)
          super(file_name_or_io, header_line: header, category: category, **args, &block)
        end

        private

        # Delimited instance used for this slice, by a single worker (thread)
        def tabular_output
          @tabular_output ||= Tabular.new(
            main: IOStreams::Tabular.new(
              columns:        tabular_output_header,
              format:         tabular_output_format,
              format_options: tabular_output_options&.deep_symbolize_keys
            )
          )
        end

        # Render the output from the perform.
        def tabular_output_render
          return unless collect_output?

          @rocket_job_output = tabular_output.render(@rocket_job_output)
        end
      end
    end
  end
end

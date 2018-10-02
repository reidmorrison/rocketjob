require 'active_support/concern'

module RocketJob
  module Batch
    module Tabular
      # For the simple case where all `input_categories` have the same format,
      # If multiple input categories are used with different formats, then use IOStreams::Tabular directly
      # instead of this plugin.
      module Input
        extend ActiveSupport::Concern

        included do
          field :tabular_input_header, type: Array, class_attribute: true, user_editable: true
          field :tabular_input_format, type: Symbol, default: :csv, class_attribute: true, user_editable: true

          validates_inclusion_of :tabular_input_format, in: IOStreams::Tabular.registered_formats

          class_attribute :tabular_input_white_list
          class_attribute :tabular_input_required
          class_attribute :tabular_input_skip_unknown

          self.tabular_input_white_list   = nil
          self.tabular_input_required     = nil
          self.tabular_input_skip_unknown = true

          before_batch :tabular_input_cleanse_header, :tabular_input_process_first_slice
          before_perform :tabular_input_render
        end

        private

        # Shared instance used for this slice, by a single worker (thread)
        def tabular_input
          @tabular_input ||= IOStreams::Tabular.new(
            columns:          tabular_input_header,
            allowed_columns:  tabular_input_white_list,
            required_columns: tabular_input_required,
            skip_unknown:     tabular_input_skip_unknown,
            format:           tabular_input_format
          )
        end

        def tabular_input_render
          @rocket_job_input = tabular_input.record_parse(@rocket_job_input) unless tabular_input_header.blank? && tabular_input.parse_header?
        end

        # Cleanse custom input header if supplied.
        def tabular_input_cleanse_header
          return unless tabular_input_header.present?

          ignored_columns = tabular_input.header.cleanse!
          logger.warn('Stripped out invalid columns from custom header', ignored_columns) unless ignored_columns.empty?

          self.tabular_input_header = tabular_input.header.columns
        end

        def tabular_input_parse_header(row)
          tabular_input.parse_header(row)

          ignored_columns = tabular_input.header.cleanse!
          logger.warn('Stripped out invalid columns from custom header', ignored_columns) unless ignored_columns.empty?

          self.tabular_input_header = tabular_input.header.columns
        end

        # Process the first slice to get the header line, unless already set.
        def tabular_input_process_first_slice
          return if tabular_input_header.present? || !tabular_input.parse_header?

          work_first_slice do |row|
            # Skip blank lines
            next if row.blank?

            if tabular_input_header.blank? && tabular_input.parse_header?
              tabular_input_parse_header(row)
            else
              if block_given?
                @rocket_job_output = yield(@rocket_job_input)
              else
                perform(row)
              end
            end
          end
        end

      end
    end
  end
end

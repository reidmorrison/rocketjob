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
          validate :tabular_input_header_present

          class_attribute :tabular_input_white_list
          class_attribute :tabular_input_required
          class_attribute :tabular_input_skip_unknown

          self.tabular_input_white_list   = nil
          self.tabular_input_required     = nil
          self.tabular_input_skip_unknown = true

          before_perform :tabular_input_render
        end

        # Extract the header line during the upload.
        #
        # Overrides: RocketJob::Batch::IO#upload
        #
        # Notes:
        # - When supplying a block the header must be set manually
        def upload(file_name_or_io = nil, **args, &block)
          # If an input header is not required, then we don't extract it'
          return super(file_name_or_io, **args, &block) unless tabular_input.parse_header?

          # If the header is already set then it is not expected in the file
          if tabular_input_header.present?
            tabular_input_cleanse_header
            return super(file_name_or_io, **args, &block)
          end

          parse_header = -> (line) do
            tabular_input.parse_header(line)
            tabular_input_cleanse_header
            self.tabular_input_header = tabular_input.header.columns
          end
          super(file_name_or_io, on_first_line: parse_header, **args, &block)
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
          ignored_columns = tabular_input.header.cleanse!
          logger.warn('Stripped out invalid columns from custom header', ignored_columns) unless ignored_columns.empty?

          self.tabular_input_header = tabular_input.header.columns
        end

        def tabular_input_header_present
          return if tabular_input_header.present? || !tabular_input.parse_header?

          errors.add(:tabular_input_header, "is required when tabular_input_format is #{tabular_input_format.inspect}")
        end
      end
    end
  end
end

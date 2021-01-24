require "active_support/concern"

module RocketJob
  module Batch
    class Tabular
      # For the simple case where all `input_categories` have the same format,
      # If multiple input categories are used with different formats, then use IOStreams::Tabular directly
      # instead of this plugin.
      module Input
        extend ActiveSupport::Concern

        included do
          field :tabular_input_header, type: Array, class_attribute: true, user_editable: true
          field :tabular_input_format, type: Mongoid::StringifiedSymbol, default: :csv, class_attribute: true, user_editable: true
          field :tabular_input_options, type: Hash, class_attribute: true

          # tabular_input_mode: [:line | :array | :hash]
          #   :line
          #     Uploads the file a line (String) at a time for processing by workers.
          #   :array
          #     Parses each line from the file as an Array and uploads each array for processing by workers.
          #   :hash
          #     Parses each line from the file into a Hash and uploads each hash for processing by workers.
          #   See IOStreams#each.
          field :tabular_input_mode, type: Mongoid::StringifiedSymbol, default: :line, class_attribute: true, user_editable: true, copy_on_restart: true

          validates_inclusion_of :tabular_input_format, in: IOStreams::Tabular.registered_formats
          validates_inclusion_of :tabular_input_mode, in: %i[line array hash row record]
          validate :tabular_input_header_present

          class_attribute :tabular_input_white_list
          class_attribute :tabular_input_required
          class_attribute :tabular_input_skip_unknown

          # Cleanse all uploaded data by removing non-printable characters
          # and any characters that cannot be converted to UTF-8
          class_attribute :tabular_input_type

          self.tabular_input_white_list   = nil
          self.tabular_input_required     = nil
          self.tabular_input_skip_unknown = true
          self.tabular_input_type         = :text

          before_perform :tabular_input_render
        end

        # Extract the header line during the upload.
        #
        # Overrides: RocketJob::Batch::IO#upload
        #
        # Notes:
        # - When supplying a block the header must be set manually
        def upload(stream = nil, **args, &block)
          input_stream = stream.nil? ? nil : IOStreams.new(stream)

          if stream && (tabular_input_type == :text)
            # Cannot change the length of fixed width lines
            replace = tabular_input_format == :fixed ? " " : ""
            input_stream.option_or_stream(:encode, encoding: "UTF-8", cleaner: :printable, replace: replace)
          end

          # If an input header is not required, then we don't extract it'
          return super(input_stream, stream_mode: tabular_input_mode, **args, &block) unless tabular_input.header?

          # If the header is already set then it is not expected in the file
          if tabular_input_header.present?
            tabular_input_cleanse_header
            return super(input_stream, stream_mode: tabular_input_mode, **args, &block)
          end

          case tabular_input_mode
          when :line
            parse_header = lambda do |line|
              tabular_input.parse_header(line)
              tabular_input_cleanse_header
              self.tabular_input_header = tabular_input.header.columns
            end
            super(input_stream, on_first: parse_header, stream_mode: :line, **args, &block)
          when :array, :row
            set_header = lambda do |row|
              tabular_input.header.columns = row
              tabular_input_cleanse_header
              self.tabular_input_header = tabular_input.header.columns
            end
            super(input_stream, on_first: set_header, stream_mode: :array, **args, &block)
          when :hash, :record
            super(input_stream, stream_mode: :hash, **args, &block)
          else
            raise(ArgumentError, "Invalid tabular_input_mode: #{stream_mode.inspect}")
          end
        end

        private

        # Shared instance used for this slice, by a single worker (thread)
        def tabular_input
          @tabular_input ||= IOStreams::Tabular.new(
            columns:          tabular_input_header,
            allowed_columns:  tabular_input_white_list,
            required_columns: tabular_input_required,
            skip_unknown:     tabular_input_skip_unknown,
            format:           tabular_input_format,
            format_options:   tabular_input_options&.deep_symbolize_keys
          )
        end

        def tabular_input_render
          return if tabular_input_header.blank? && tabular_input.header?

          @rocket_job_input = tabular_input.record_parse(@rocket_job_input)
        end

        # Cleanse custom input header if supplied.
        def tabular_input_cleanse_header
          ignored_columns = tabular_input.header.cleanse!
          logger.warn("Stripped out invalid columns from custom header", ignored_columns) unless ignored_columns.empty?

          self.tabular_input_header = tabular_input.header.columns
        end

        def tabular_input_header_present
          if tabular_input_header.present? || !tabular_input.header? || (tabular_input_mode == :hash || tabular_input_mode == :record)
            return
          end

          errors.add(:tabular_input_header, "is required when tabular_input_format is #{tabular_input_format.inspect}")
        end
      end
    end
  end
end

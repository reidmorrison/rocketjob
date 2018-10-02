require 'active_support/concern'

module RocketJob
  module Batch
    module Tabular
      autoload :Input, 'rocket_job/batch/tabular/input'
      autoload :Output, 'rocket_job/batch/tabular/output'

      extend ActiveSupport::Concern

      include Input
      include Output

      private

      # Calculate the output when not already supplied
      # Return the output header
      # By Default it just returns the input header, override to replace
      def tabular_output_set_header
        self.tabular_output_header ||= tabular_input_header
      end

      # Overwites RocketJob::Batch::Tabular::Input
      #
      # If a block is supplied it will be called for each row instead of calling `#perform`
      # Notes:
      # - No before or after performs will be called other than:
      #     before_perform :tabular_input_render
      #     after_perform  :tabular_output_render
      def tabular_input_process_first_slice
        if tabular_input_header.present? && tabular_output.requires_header?
          # When the input header is supplied in the job, write the output header in its own slice.
          tabular_output_set_header
          tabular_output_write_header
          # No need to process the first slice since the header has already been supplied.
          return #unless block_given?
        end

        work_first_slice do |row|
          # Skip blank lines
          next if row.blank?

          if tabular_input_header.blank? && tabular_input.requires_header?
            tabular_input_parse_header(row)
            # When the header is extracted from the first line in the file
            # set the output header and return it so that it is written to the output file.
            tabular_output_set_header
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


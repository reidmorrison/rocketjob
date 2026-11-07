module RocketJob
  module Category
    # How an input category with a schema reads the header row of a file that is uploaded into it, see
    # Input#extract_header_callback.
    #
    # The workers read every record of the input by the header row that its upload read, see Input#columns. So when the
    # input already holds the records of an earlier upload, the category keeps those columns when the upload fails,
    # such as for a header row that does not match the schema, or a line that `validate_rows` cannot parse.
    module InputSchemaHeader
      # Yields the lambda that reads the header row of a file that is uploaded into this category, see
      # Input#extract_header_callback, and returns what the block returns. Supply `uploaded: true` when the input already
      # holds the records of an earlier upload: when the block raises, the category then keeps the columns that those
      # records are read by. Either way its tabular is then built again from its columns, see #schema_header_callback.
      def upload_header(on_first, uploaded: false)
        uploaded_columns = columns
        yield extract_header_callback(on_first, uploaded: uploaded)
      rescue Exception
        self.columns = uploaded_columns if uploaded
        raise
      ensure
        @tabular = nil if uploaded
      end

      private

      # Returns the lambda that reads the header row of a file with a schema. Its columns are matched to the fields of
      # the schema, which raises IOStreams::Errors::InvalidHeader when they do not match, and are kept as they are in
      # the file, see Input#columns. A blank row before it, which IOStreams does not read as a header row, such as a line
      # of only commas, is skipped, as IOStreams skips it when it reads the header row itself.
      #
      # An upload reads the header row of its own file, rather than keep the columns of an earlier one, such as those
      # that a job scheduled again copies from its last run, see Plugins::Cron. When the input already holds the
      # records of an earlier upload, see `uploaded`, a tabular of its own reads the header row, and the lines of the
      # file while it is uploaded, see Input#each_record, so that the columns stay those of the earlier upload until it
      # is read.
      def schema_header_callback(on_first, uploaded)
        if uploaded && columns.present?
          @tabular = schema_tabular(nil)
        else
          self.columns = nil
          @tabular     = nil
        end
        return first_record_callback(on_first) unless tabular.header?

        lambda do |line|
          tabular.read_header(line)
          next false if tabular.header?

          self.columns = tabular.header.columns
          on_first&.call(line)
          true
        end
      end
    end
  end
end

module RocketJob
  module Category
    # How an input category proposes the schema that replaces its deprecated options, see #schema_proposal and
    # RocketJob::SchemaProposal, from what those options did in Rocket Job 7.0.
    module InputSchemaProposal
      # What to check before moving column restrictions to a schema, see #schema_proposal.
      NON_ASCII_NOTE = "A name that 7.0 cleansed from a column with letters that are not ASCII lost them, such as " \
                       "prnom for Prénom, which the schema cleanses to prénom. Rename such a field, or the schema " \
                       "skips its column without an error. Read a recent file with #dry_run to find them.".freeze

      # What to check before moving a fixed width layout to a schema, see #schema_proposal.
      LAYOUT_NOTE = "A value that is not of the type of its field, such as letters in an integer field, raises " \
                    "IOStreams::Errors::InvalidValue, where the layout read it as 0. Each width counts the characters " \
                    "of the UTF-8 text of a line.".freeze
      private_constant :NON_ASCII_NOTE, :LAYOUT_NOTE

      # Returns [RocketJob::SchemaProposal] the schema proposed to replace this category's deprecated options at the
      # supplied place, such as "ImportJob, input category main", or nil when it sets none. Changes nothing.
      #
      # The schema reads the files as 7.0 read them with those options, which is not always what they say: 7.0 did not
      # apply `allowed_columns`, `required_columns` or `skip_unknown` to JSON records, to `columns` supplied for a file
      # without a header row, or with `header_cleanser` :none, so they are removed there rather than described in the
      # schema, and the proposal says so.
      #
      # `defined` is the category of the same name that the job class defines, for a saved job: when it has no columns,
      # the columns of this category, in a format with a header row, hold the header row of a file, which an upload read,
      # rather than columns that the application set. They are kept for a job that has `uploaded` its input, and removed
      # otherwise, since a scheduled job copies them from its last run, so that each upload reads its own header row.
      def schema_proposal(where, defined: nil, uploaded: false)
        names = deprecated_options_set
        names << "mode" if mode == :array
        return if names.empty?

        notes   = []
        columns = self.columns
        if names.include?("columns") && defined && defined.columns.blank? && header_row_format?
          columns = nil
          names.delete("columns")
          unless uploaded
            names << "columns"
            notes << "Its columns hold the header row of an earlier upload, which a scheduled job copies to its next " \
                     "run. They are removed, so that each upload reads the header row of its own file."
          end
          return if names.empty?
        end
        return schema_kept_proposal(where, names) if schema.present?

        schema, error = proposed_schema(columns, notes)
        # A layout that cannot be translated keeps its settings until its schema is written by hand.
        changes = error ? {} : default_settings(names)
        changes["schema"] = schema if schema
        RocketJob::SchemaProposal.new(where: where, category: self, changes: changes, notes: notes, error: error)
      end

      private

      # The proposal for a category that already has a schema, such as one that a Dirmon entry's properties merge into a
      # job class with a schema, whose deprecated options are only removed.
      def schema_kept_proposal(where, names)
        RocketJob::SchemaProposal.new(
          where:    where,
          category: self,
          changes:  default_settings(names),
          notes:    ["It already has a schema, so its deprecated options are removed, rather than described in another one."]
        )
      end

      # Returns [Array] the schema that replaces this category's column options and layout, read with the supplied
      # columns, and nil, or nil and why the layout cannot be translated. Adds what to check to the supplied notes.
      def proposed_schema(columns, notes)
        restrictions = %w[allowed_columns required_columns].select { |name| public_send(name).present? }
        restrictions << "skip_unknown" if skip_unknown
        unless tabular?
          notes << "Without a format the category's records are not parsed, so its deprecated options had no " \
                   "effect, and are removed."
          return [nil, nil]
        end
        return proposed_layout_schema(columns, restrictions, notes) if format_options.present?

        return keyed_schema(columns, restrictions, notes) if %i[json hash].include?(format)

        if columns.present?
          notes << never_applied(restrictions, "to the columns of a file without a header row") unless restrictions.empty?
          if format == :auto
            notes << "With format :auto, 7.0 read these columns as those of a CSV or PSV file without a header row, " \
                     "and narrowed the keys of a JSON file to them, while the schema describes only the former."
          end
          return [headerless_schema(columns), nil]
        end
        if header_cleanser == :none
          notes << never_applied(restrictions, "with header_cleanser :none") unless restrictions.empty?
          return [{"fieldsMatch" => "subset", "extraColumns" => "keep", "fields" => []}, nil]
        end
        if allowed_columns.blank? && required_columns.blank?
          notes << "skip_unknown had no effect without allowed_columns, so it is removed." if skip_unknown
          return [nil, nil]
        end

        notes << auto_format_note(restrictions) if format == :auto
        notes << NON_ASCII_NOTE
        [restricted_schema, nil]
      end

      def proposed_layout_schema(columns, restrictions, notes)
        unless restrictions.empty?
          notes << "#{restrictions.join(', ')} #{restrictions.size == 1 ? 'is' : 'are'} removed with the layout. If " \
                   "they changed the records of its files, describe that in the schema, and compare with #dry_run."
        end
        notes << LAYOUT_NOTE
        layout_schema(columns)
      end

      # The schema of JSON records, or Hashes, whose keys 7.0 narrowed to the supplied columns, and to which it applied no
      # column restrictions.
      def keyed_schema(columns, restrictions, notes)
        unless restrictions.empty?
          notes << never_applied(restrictions, "to #{format == :json ? 'JSON records' : 'Hash records'}")
        end
        return [nil, nil] if columns.blank?

        notes << "7.0 narrowed each record to its columns, matching its keys exactly, and gave nil for a column that a " \
                 "record did not have. The schema matches the keys whatever their case, spaces and punctuation, and " \
                 "leaves out a field that a record does not have, so read a recent file with #dry_run."
        [{"fieldsMatch" => "partial", "fields" => columns.compact.map { |name| {"name" => name.to_s} }}, nil]
      end

      # The schema of a file without a header row, whose columns are given, as 7.0 named them, uncleansed. A nil column
      # is a skipped field, which holds its place.
      def headerless_schema(columns)
        fields = columns.each_with_index.map do |name, index|
          name.nil? ? {"name" => "column_#{index + 1}", "skip" => true} : {"name" => name.to_s}
        end
        {"header" => false, "fields" => fields}
      end

      # The schema of a file with a header row whose cleansed columns are restricted, keyed as 7.0 keyed them.
      def restricted_schema
        allowed  = allowed_columns.to_a.map(&:to_s)
        required = required_columns.to_a.map(&:to_s)
        fields   = (allowed | required).map do |name|
          field = {"name" => name}
          field.merge!("constraints" => {"required" => true}, "allowBlank" => true) if required.include?(name)
          field
        end
        schema =
          if allowed.empty?
            # required_columns alone kept every other column of the file.
            {"fieldsMatch" => "subset", "extraColumns" => "keep"}
          else
            {"fieldsMatch" => skip_unknown ? "partial" : "superset"}
          end
        schema.merge("fields" => fields, "keyType" => "cleansed")
      end

      def auto_format_note(restrictions)
        "With format :auto, 7.0 applied #{restrictions.join(', ')} to CSV and PSV files, but not to JSON files, which " \
          "the schema also restricts, and whose keys it cleanses."
      end

      def never_applied(names, where)
        "7.0 did not apply #{names.join(', ')} #{where}, so #{names.size == 1 ? 'it is' : 'they are'} removed rather " \
          "than described in the schema."
      end

      # Returns [true|false] whether this category's format reads a header row from its files, such as CSV.
      def header_row_format?
        IOStreams::Tabular.new(format: format == :auto ? nil : format, file_name: file_name).header?
      rescue StandardError
        false
      end
    end
  end
end

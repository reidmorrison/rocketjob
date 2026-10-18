module Compat
  module Scenarios
    # Scenarios 1-8: an input category of CSV with each of the column options, and the same in the :array and :hash
    # upload modes, see .mode_variants.
    module Csv
      # A header with mixed case, spaces and punctuation, and a column that the allowed columns leave out.
      DATA       = "First Name,Last-Name,Zip Code,Extra\nJack,Jones,12345,x\nJill,,54321,y\n".freeze
      HEADERLESS = "Jack,12345\nJill,54321\n".freeze
      ALLOWED    = %w[first_name last_name zip_code].freeze

      BASE = [
        {id: "A01_csv_default", desc: "format: :csv alone (header_cleanser :default)",
         input: {format: :csv}},
        {id: "A02_csv_header_cleanser_none", desc: "header_cleanser: :none",
         input: {format: :csv, header_cleanser: :none}},
        {id: "A03_csv_allowed_skip_false", desc: "allowed_columns, skip_unknown: false, extra column",
         input: {format: :csv, allowed_columns: ALLOWED, skip_unknown: false}},
        {id: "A04_csv_allowed_skip_true", desc: "allowed_columns, skip_unknown: true, extra column",
         input: {format: :csv, allowed_columns: ALLOWED, skip_unknown: true}},
        {id: "A05a_csv_required_present", desc: "required_columns: [zip_code] (present)",
         input: {format: :csv, required_columns: %w[zip_code]}},
        {id: "A05b_csv_required_absent", desc: "required_columns: [missing] (absent)",
         input: {format: :csv, required_columns: %w[missing]}},
        {id: "A06a_csv_allowed_required", desc: "allowed_columns + required_columns + skip_unknown: true",
         input: {format: :csv, allowed_columns: ALLOWED, required_columns: %w[zip_code], skip_unknown: true}},
        {id: "A06b_csv_allowed_required_absent", desc: "allowed + required [zip_code, missing] + skip_unknown",
         input: {format: :csv, allowed_columns: ALLOWED + %w[missing], required_columns: %w[zip_code missing],
                 skip_unknown: true}},
        {id: "A07a_csv_headerless_columns", desc: "headerless file, columns: [name zip]",
         input: {format: :csv, columns: %w[name zip]}, data: HEADERLESS},
        {id: "A07b_csv_headerless_columns_mixed_case", desc: "headerless file, columns: [\"Name\", \"Zip Code\"]",
         input: {format: :csv, columns: ["Name", "Zip Code"]}, data: HEADERLESS},
        {id: "A07c_csv_headerless_columns_allowed", desc: "headerless, columns [name zip extra] + allowed [name zip] + skip",
         input: {format: :csv, columns: %w[name zip extra], allowed_columns: %w[name zip], skip_unknown: true},
         data: "Jack,12345,x\nJill,54321,y\n"},
        {id: "A08a_csv_cleanser_none_allowed_raw", desc: "header_cleanser :none + allowed raw names + skip",
         input: {format: :csv, header_cleanser: :none, allowed_columns: ["First Name", "Last-Name", "Zip Code"],
                 skip_unknown: true}},
        {id: "A08b_csv_cleanser_none_allowed_cleansed", desc: "header_cleanser :none + allowed cleansed names",
         input: {format: :csv, header_cleanser: :none, allowed_columns: ALLOWED, skip_unknown: true}},
        {id: "A09_csv_non_ascii_header", desc: "format: :csv, header and value with a non-ASCII letter",
         input: {format: :csv}, data: "Prénom,Zip Code\nJosé,12345\n"}
      ].freeze

      # The scenarios of BASE that .mode_variants runs again in each upload mode.
      MODE_BASE = BASE.first(13).freeze

      # Returns [Array<Hash>] the definitions of these scenarios.
      def self.all
        BASE + mode_variants
      end

      # Returns [Array<Hash>] scenarios 1-7 again in the :array and :hash upload modes, as the category's mode, and as
      # the stream_mode of upload.
      def self.mode_variants
        MODE_BASE.flat_map do |base|
          [
            variant(base, "mode_array", "input mode: :array", input: base[:input].merge(mode: :array)),
            variant(base, "mode_hash", "input mode: :hash", input: base[:input].merge(mode: :hash)),
            variant(base, "stream_array", "upload(stream_mode: :array)", upload_args: {stream_mode: :array}),
            variant(base, "stream_hash", "upload(stream_mode: :hash)", upload_args: {stream_mode: :hash})
          ]
        end
      end

      def self.variant(base, suffix, desc, **changes)
        base.merge(id: "#{base[:id]}__#{suffix}", desc: "#{base[:desc]}; #{desc}", **changes)
      end
      private_class_method :variant
    end
  end
end

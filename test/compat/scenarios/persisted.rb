module Compat
  module Scenarios
    # Scenario 12: batch jobs that v7 creates, uploads and saves, without processing them, which v7 and v8 then load
    # from the shared database and process, see PersistedJobs. Each job class is defined the same way under both
    # versions, so that the `_type` of each saved job names a class in both.
    module Persisted
      ALLOWED = Csv::ALLOWED

      DEFINITIONS = [
        {id: "P01_csv_allowed_skip", desc: "csv + allowed_columns + skip_unknown, output csv columns",
         input: {format: :csv, allowed_columns: ALLOWED, skip_unknown: true},
         outputs: [{format: :csv, columns: %w[zip_code first_name]}]},
        {id: "P02_csv_headerless_columns", desc: "headerless csv, columns [name zip]",
         input: {format: :csv, columns: %w[name zip]}, data: Csv::HEADERLESS},
        {id: "P03_fixed_format_options_in_out", desc: "fixed format_options on input and output (filler, remainder, " \
                                                      "integer, float, truncate: false)",
         input: {format: :fixed, format_options: {layout: Formats::LAYOUT, truncate: false}},
         outputs: [{format: :fixed, format_options: {layout: Formats::LAYOUT, truncate: false}}],
         data: Formats::FIXED, file_name: "x.txt"},
        {id: "P04_fixed_symbol_keys", desc: "fixed format_options with Symbol keys and types",
         input: {format: :fixed, format_options: {layout: Formats::SYMBOL_LAYOUT}},
         data: Formats::SYMBOL_FIXED, file_name: "x.txt"},
        {id: "P05_csv_cleanser_none_allowed", desc: "header_cleanser :none + allowed raw names + skip_unknown",
         input: {format: :csv, header_cleanser: :none, allowed_columns: ["First Name", "Zip Code"], skip_unknown: true}},
        {id: "P06_json_allowed_skip", desc: "json + allowed_columns + skip_unknown",
         input: {format: :json, allowed_columns: ALLOWED, skip_unknown: true},
         data: Formats::JSON_LINES, file_name: "x.json"},
        {id: "P07_csv_required_output_columns", desc: "csv + required_columns, output csv columns",
         input: {format: :csv, required_columns: %w[zip_code]}, outputs: [{format: :csv, columns: %w[zip_code]}]},
        {id: "P08_output_fixed_columns_array", desc: "output fixed format_options + columns, Array result",
         input: {format: :csv}, outputs: [{format: :fixed, columns: %w[name zip], format_options: Outputs::NAME_ZIP}],
         transform: ->(r) { [r["first_name"], r["zip_code"]] }},
        {id: "P09_csv_stream_mode_array_allowed", desc: "csv + allowed_columns + skip_unknown, upload(stream_mode: :array)",
         input: {format: :csv, allowed_columns: ALLOWED, skip_unknown: true}, upload_args: {stream_mode: :array}},
        {id: "P10_json_headerless_columns_output_columns", desc: "csv columns + header_cleanser none, output json columns",
         input: {format: :csv, columns: %w[Name Zip], header_cleanser: :none},
         outputs: [{format: :json, columns: %w[Zip]}], data: Csv::HEADERLESS}
      ].freeze

      # Returns [Array<Compat::Scenario>] these scenarios.
      def self.all
        Scenarios.build(DEFINITIONS)
      end
    end
  end
end

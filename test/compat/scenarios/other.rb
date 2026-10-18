module Compat
  module Scenarios
    # Scenario 11 and the other ways that an application uploads: a job built from properties, as a Dirmon entry or
    # an UploadFileJob builds it, a job that a worker reloads before processing it, records written to the block of
    # upload, the documented way to keep the v7 column restrictions, and options supplied to upload itself.
    module Other
      ALLOWED = Csv::ALLOWED

      LAYOUT_PROPERTIES = {
        "layout" => [{"size" => 10, "key" => "name"}, {"size" => 5, "key" => "zip", "type" => "integer"}]
      }.freeze
      UPLOAD_LAYOUT = {layout: [{size: 10, key: "name"}, {size: 5, key: "zip", type: :integer}]}.freeze

      PROPERTIES = [
        {id: "E01_props_csv_allowed_output_columns", desc: "from_properties: csv + allowed_columns + skip_unknown, " \
                                                           "output csv columns",
         input: {}, outputs: [{}],
         properties: {
           "input_categories"  => [{"name" => "main", "format" => "csv", "allowed_columns" => ALLOWED, "skip_unknown" => true}],
           "output_categories" => [{"name" => "main", "format" => "csv", "columns" => %w[zip_code first_name]}]
         }},
        {id: "E02_props_fixed_format_options", desc: "from_properties: fixed + format_options (String keys)",
         input: {}, data: Formats::SYMBOL_FIXED, file_name: "x.txt",
         properties: {"input_categories" => [{"name" => "main", "format" => "fixed", "format_options" => LAYOUT_PROPERTIES}]}},
        {id: "E03_props_headerless_columns_cleanser_none", desc: "from_properties: csv, columns + header_cleanser none",
         input: {}, data: Csv::HEADERLESS,
         properties: {"input_categories" => [{"name" => "main", "format" => "csv", "columns" => %w[Name Zip],
                                              "header_cleanser" => "none"}]}},
        {id: "E04_props_output_fixed_format_options", desc: "from_properties: output fixed + format_options",
         input: {format: :csv}, outputs: [{}], transform: ->(r) { {"name" => r["first_name"], "zip" => r["zip_code"].to_i} },
         properties: {"output_categories" => [{"name" => "main", "format" => "fixed", "format_options" => LAYOUT_PROPERTIES}]}},
        {id: "E05_props_output_fixed_format_options_columns", desc: "from_properties: output fixed + format_options + columns",
         input: {format: :csv}, outputs: [{}], transform: ->(r) { [r["first_name"], r["zip_code"]] },
         properties: {"output_categories" => [{"name" => "main", "format" => "fixed", "format_options" => LAYOUT_PROPERTIES,
                                               "columns" => %w[name zip]}]}}
      ].freeze

      RELOADED = [
        {id: "F01_reloaded_plain_csv", desc: "format: :csv alone, processed by a reloaded instance",
         input: {format: :csv}, reload: true},
        {id: "F02_reloaded_csv_allowed_skip", desc: "csv + allowed_columns + skip_unknown, reloaded",
         input: {format: :csv, allowed_columns: ALLOWED, skip_unknown: true}, reload: true},
        {id: "F03_reloaded_fixed_format_options", desc: "fixed format_options (Symbol keys), reloaded",
         input: {format: :fixed, format_options: {layout: Formats::SYMBOL_LAYOUT}}, data: Formats::SYMBOL_FIXED,
         file_name: "x.txt", reload: true},
        {id: "F04_reloaded_output_csv_columns", desc: "output csv columns [b a], reloaded",
         input: {format: :csv}, outputs: [{format: :csv, columns: %w[b a]}], transform: Outputs::AB, reload: true}
      ].freeze

      LINES = Csv::DATA.lines.map(&:chomp).freeze

      BLOCKS = [
        {id: "G01_block_csv_lines", desc: "upload with a block: CSV header line and lines",
         input: {format: :csv}, via: :block, records: LINES},
        {id: "G02_block_csv_allowed_skip", desc: "upload with a block: CSV lines, allowed_columns + skip_unknown",
         input: {format: :csv, allowed_columns: ALLOWED, skip_unknown: true}, via: :block, records: LINES},
        {id: "G03_block_arrays_mode_array", desc: "upload with a block: header Array and Arrays, input mode: :array",
         input: {format: :csv, mode: :array}, via: :block,
         records: [["First Name", "Zip Code"], %w[Jack 12345], %w[Jill 54321]]}
      ].freeze

      # Sets IOStreams.enforce_column_restrictions to false, the documented way to keep the v7 column restrictions,
      # and returns the lambda that restores it.
      ENFORCE_FALSE = lambda do
        before = IOStreams.enforce_column_restrictions?
        IOStreams.enforce_column_restrictions = false
        -> { IOStreams.instance_variable_set(:@enforce_column_restrictions, before) }
      end

      # The scenarios that .enforce_false runs again with ENFORCE_FALSE.
      ENFORCE_FALSE_IDS = %w[
        A07c_csv_headerless_columns_allowed A08a_csv_cleanser_none_allowed_raw A08b_csv_cleanser_none_allowed_cleansed
        A04_csv_allowed_skip_true__mode_hash C04_json_allowed_skip_false C05_json_allowed_skip_true
        C06a_json_required_absent C10a_auto_json_allowed
      ].freeze

      UPLOAD_OPTIONS = [
        {id: "I01_upload_stream_array_format_options", desc: "upload(stream_mode: :array, format: :fixed, format_options:)",
         input: {format: :fixed, format_options: UPLOAD_LAYOUT}, data: Formats::SYMBOL_FIXED, file_name: "x.txt",
         upload_args: {stream_mode: :array, format: :fixed, format_options: UPLOAD_LAYOUT}},
        {id: "I02_upload_stream_hash_format_options", desc: "upload(stream_mode: :hash, format: :fixed, format_options:)",
         input: {format: :fixed, format_options: UPLOAD_LAYOUT}, data: Formats::SYMBOL_FIXED, file_name: "x.txt",
         upload_args: {stream_mode: :hash, format: :fixed, format_options: UPLOAD_LAYOUT}},
        {id: "I03_no_format_stream_hash", desc: "input category without a format, upload(stream_mode: :hash) of x.csv",
         input: {}, upload_args: {stream_mode: :hash}},
        {id: "I04_no_format_stream_array", desc: "input category without a format, upload(stream_mode: :array) of x.csv",
         input: {}, upload_args: {stream_mode: :array}},
        {id: "I05_no_format_stream_hash_allowed", desc: "no format, upload(stream_mode: :hash, allowed_columns:, skip_unknown: true)",
         input: {}, upload_args: {stream_mode: :hash, allowed_columns: %w[first_name zip_code], skip_unknown: true}}
      ].freeze

      # Returns [Array<Hash>] the definitions of these scenarios.
      def self.all
        PROPERTIES + RELOADED + BLOCKS + enforce_false + UPLOAD_OPTIONS
      end

      # Returns [Array<Hash>] the scenarios of ENFORCE_FALSE_IDS again, with IOStreams.enforce_column_restrictions false.
      def self.enforce_false
        (Csv.all + Formats::ALL).select { |definition| ENFORCE_FALSE_IDS.include?(definition[:id]) }.map do |definition|
          definition.merge(
            id:         "H_#{definition[:id]}",
            desc:       "#{definition[:desc]}; IOStreams.enforce_column_restrictions = false",
            setup:      ENFORCE_FALSE,
            setup_desc: "IOStreams.enforce_column_restrictions = false"
          )
        end
      end
    end
  end
end

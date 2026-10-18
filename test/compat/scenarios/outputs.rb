module Compat
  module Scenarios
    # Scenario 10: output categories, CSV, PSV and JSON with columns, fixed width with format_options, nils, and
    # results for a named output category, each from the records of the CSV file of Csv::DATA.
    module Outputs
      # name 10, filler 2, zip 5 (integer), amount 8 (float, 2 decimals), rest (remainder)
      FIXED_LAYOUT = Formats::LAYOUT
      NAME_ZIP     = {layout: Formats::STRING_LAYOUT}.freeze
      NUMBERS      = {layout: [{size: 5, key: "zip", type: :integer}, {size: 8, key: "amount", type: :float}]}.freeze
      TIME         = Time.utc(2026, 10, 13, 9, 30)

      AB = ->(r) { {"a" => r["first_name"], "b" => r["zip_code"], "c" => "c"} }

      # Returns [RocketJob::Batch::Results] a result of the supplied value for each of the supplied output categories.
      RESULTS = lambda do |value, *categories|
        categories.each_with_object(RocketJob::Batch::Results.new) do |category, results|
          results << RocketJob::Batch::Result.new(category, value)
        end
      end

      DEFINITIONS = [
        {id: "D01_out_csv_columns_reordered", desc: "output csv columns [b a] (subset, reordered), Hash result",
         outputs: [{format: :csv, columns: %w[b a]}], transform: AB},
        {id: "D02_out_csv_columns_symbol_keys", desc: "output csv columns [b a], Hash result with Symbol keys",
         outputs: [{format: :csv, columns: %w[b a]}], transform: ->(r) { {a: r["first_name"], b: r["zip_code"]} }},
        {id: "D03_out_csv_columns_mixed_case_keys", desc: "output csv columns [b a], result keys \"A\", \"B\"",
         outputs: [{format: :csv, columns: %w[b a]}], transform: ->(r) { {"A" => r["first_name"], "B" => r["zip_code"]} }},
        {id: "D04_out_csv_columns_array_result", desc: "output csv columns [b a], Array result",
         outputs: [{format: :csv, columns: %w[b a]}], transform: ->(r) { [r["zip_code"], r["first_name"]] }},
        {id: "D05_out_fixed_format_options", desc: "output fixed format_options (filler, integer, float, remainder), " \
                                                   "truncate: false",
         outputs: [{format: :fixed, format_options: {layout: FIXED_LAYOUT, truncate: false}}],
         transform: ->(r) { {"name" => r["first_name"], "zip" => r["zip_code"].to_i, "amount" => 1.5, "rest" => "tail #{r['last_name']}"} }},
        {id: "D06_out_fixed_truncate_false_too_long", desc: "output fixed truncate: false, value longer than column",
         outputs: [{format: :fixed, format_options: {layout: FIXED_LAYOUT, truncate: false}}],
         transform: ->(r) { {"name" => "#{r['first_name']}-Longername", "zip" => 1, "amount" => 1.5, "rest" => ""} }},
        {id: "D07_out_fixed_truncate_default_too_long", desc: "output fixed (truncate default), value longer than column",
         outputs: [{format: :fixed, format_options: {layout: FIXED_LAYOUT}}],
         transform: ->(r) { {"name" => "#{r['first_name']}-Longername", "zip" => 1, "amount" => 1.5, "rest" => ""} }},
        {id: "D08a_out_fixed_columns_array", desc: "output fixed format_options + columns [name zip], Array result",
         outputs: [{format: :fixed, columns: %w[name zip], format_options: NAME_ZIP}],
         transform: ->(r) { [r["first_name"], r["zip_code"]] }},
        {id: "D08b_out_fixed_columns_hash", desc: "output fixed format_options + columns [name zip], Hash result",
         outputs: [{format: :fixed, columns: %w[name zip], format_options: NAME_ZIP}],
         transform: ->(r) { {"name" => r["first_name"], "zip" => r["zip_code"], "other" => "x"} }},
        {id: "D08c_out_fixed_no_columns_array", desc: "output fixed format_options without columns, Array result",
         outputs: [{format: :fixed, format_options: NAME_ZIP}], transform: ->(r) { [r["first_name"], r["zip_code"]] }},
        {id: "D09_out_json", desc: "output json, Hash result with String, Integer, Float, nil",
         outputs: [{format: :json}],
         transform: ->(r) { {"name" => r["first_name"], "zip" => r["zip_code"].to_i, "amount" => 1.5, "none" => nil} }},
        {id: "D10_out_json_columns", desc: "output json columns [b a]",
         outputs: [{format: :json, columns: %w[b a]}], transform: AB},
        {id: "D11a_out_nils_true", desc: "output csv columns [a], nils: true, nil result for Jill",
         outputs: [{format: :csv, columns: %w[a], nils: true}],
         transform: ->(r) { r["first_name"] == "Jill" ? nil : {"a" => r["first_name"]} }},
        {id: "D11b_out_nils_false", desc: "output csv columns [a], nils: false, nil result for Jill",
         outputs: [{format: :csv, columns: %w[a], nils: false}],
         transform: ->(r) { r["first_name"] == "Jill" ? nil : {"a" => r["first_name"]} }},
        {id: "D11c_out_plain_nils_true", desc: "output without format, nils: true, String or nil result",
         outputs: [{nils: true}], transform: ->(r) { r["first_name"] == "Jill" ? nil : r["first_name"] }},
        {id: "D12a_out_result_named_category", desc: "Batch::Result to a second named output category",
         outputs: [{format: :csv, columns: %w[a b]}, {name: :invalid, format: :csv, columns: %w[reason value]}],
         transform: lambda do |r|
           if r["last_name"].nil?
             RocketJob::Batch::Result.new(:invalid, {"reason" => "missing last name", "value" => r["first_name"]})
           else
             {"a" => r["first_name"], "b" => r["last_name"]}
           end
         end},
        {id: "D12b_out_results_both_categories", desc: "Batch::Results to main and a named output category",
         outputs: [{format: :csv, columns: %w[a]}, {name: :audit, format: :json}],
         transform: lambda do |r|
           results = RocketJob::Batch::Results.new
           results << RocketJob::Batch::Result.new(:main, {"a" => r["first_name"]})
           results << RocketJob::Batch::Result.new(:audit, {"zip" => r["zip_code"]})
           results
         end},
        {id: "D13_out_psv_columns", desc: "output psv columns [b a], value with | and a line break",
         outputs: [{format: :psv, columns: %w[b a]}],
         transform: ->(r) { {"a" => "#{r['first_name']}|x\ny", "b" => r["zip_code"]} }},
        {id: "D14_out_csv_time_bigdecimal", desc: "output csv Time and BigDecimal values",
         outputs: [{format: :csv, columns: %w[t d]}],
         transform: ->(_r) { {"t" => TIME, "d" => BigDecimal("12.50")} }},
        {id: "D15_out_csv_no_columns", desc: "output csv without columns, Hash result",
         outputs: [{format: :csv}], transform: AB},
        {id: "D16_out_json_types", desc: "output json: Time, BigDecimal, Date, Symbol, Float values",
         outputs: [{format: :json}],
         transform: ->(_r) { {"t" => TIME, "d" => BigDecimal("12.50"), "day" => Date.new(2026, 10, 13), "s" => :sym, "f" => 1.0} }},
        {id: "D16b_out_json_csv_fractional_time", desc: "output json and csv: Time with microseconds",
         outputs: [{format: :json}, {name: :csv, format: :csv, columns: %w[t]}],
         transform: ->(_r) { RESULTS.call({"t" => Time.utc(2026, 10, 13, 9, 30, 0, 123_456)}, :main, :csv) }},
        {id: "D17_out_csv_types", desc: "output csv: Date, Symbol, true, false, Float, Integer, nil, empty String",
         outputs: [{format: :csv, columns: %w[day s yes no f i none empty]}],
         transform: ->(_r) { {"day" => Date.new(2026, 10, 13), "s" => :sym, "yes" => true, "no" => false, "f" => 1.0, "i" => 7, "none" => nil, "empty" => ""} }},
        {id: "D18a_out_fixed_float_rounding", desc: "output fixed float decimals 2: 1.005, 2.675",
         outputs: [{format: :fixed, format_options: {layout: [{size: 10, key: "name"}, {size: 8, key: "amount", type: :float, decimals: 2}]}}],
         transform: ->(r) { {"name" => r["first_name"], "amount" => r["first_name"] == "Jack" ? 1.005 : 2.675} }},
        {id: "D18b_out_fixed_negative", desc: "output fixed integer -12, float -1.5",
         outputs: [{format: :fixed, format_options: NUMBERS}], transform: ->(_r) { {"zip" => -12, "amount" => -1.5} }},
        {id: "D18c_out_fixed_numeric_strings", desc: "output fixed integer \"42\", float \"3.10\" as Strings",
         outputs: [{format: :fixed, format_options: NUMBERS}], transform: ->(_r) { {"zip" => "42", "amount" => "3.10"} }},
        {id: "D18d_out_fixed_nil_numbers", desc: "output fixed integer and float nil",
         outputs: [{format: :fixed, format_options: NUMBERS}], transform: ->(_r) { {"zip" => nil, "amount" => nil} }},
        {id: "D18e_out_fixed_string_line_break", desc: "output fixed string with a line break, and a Symbol key",
         outputs: [{format: :fixed, format_options: NAME_ZIP}], transform: ->(r) { {"name" => "Ja\nck", zip: r["zip_code"]} }},
        {id: "D18f_out_fixed_symbol_layout_keys", desc: "output fixed layout with Symbol keys, Hash result with String keys",
         outputs: [{format: :fixed, format_options: {layout: [{size: 10, key: :name}, {size: 5, key: :zip}]}}],
         transform: ->(r) { {"name" => r["first_name"], "zip" => r["zip_code"]} }},
        {id: "D18g_out_fixed_symbol_layout_symbol_result", desc: "output fixed layout with Symbol keys, Hash result with Symbol keys",
         outputs: [{format: :fixed, format_options: {layout: [{size: 10, key: :name}, {size: 5, key: :zip}]}}],
         transform: ->(r) { {name: r["first_name"], zip: r["zip_code"]} }},
        {id: "D19_out_csv_json_numbers", desc: "output csv and json: BigDecimal and Float edge values",
         outputs: [{format: :csv, columns: %w[a b c d e f]}, {name: :json, format: :json}],
         transform: lambda do |_r|
           values = {"a" => BigDecimal("0.0000001"), "b" => BigDecimal("1e20"), "c" => BigDecimal("12.50"),
                     "d" => BigDecimal("-0.5"), "e" => 1e20, "f" => 0.1 + 0.2}
           RESULTS.call(values, :main, :json)
         end}
      ].freeze

      # Each scenario reads the CSV file of Csv::DATA.
      ALL = DEFINITIONS.map { |definition| {input: {format: :csv}}.merge(definition) }.freeze
    end
  end
end

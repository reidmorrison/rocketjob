module Compat
  module Scenarios
    # Scenario 9: the other formats of an input category, PSV, JSON, fixed width with format_options and :auto, and
    # CSV files that are harder to read, such as quoted values, ragged rows and headers that are not ASCII.
    module Formats
      PSV        = "First Name|Last-Name|Zip Code|Extra\nJack|Jones|12345|x\nJill||54321|\n".freeze
      JSON_LINES = (%({"First Name":"Jack","Last-Name":"Jones","Zip Code":"12345","Extra":"x"}\n) +
                    %({"First Name":"Jill","Zip Code":"54321","Extra":"y"}\n)).freeze

      # name 10, filler 2, zip 5 (integer), amount 8 (float, 2 decimals), rest (remainder)
      LAYOUT = [
        {size: 10, key: "name"},
        {size: 2},
        {size: 5, key: "zip", type: :integer},
        {size: 8, key: "amount", type: :float, decimals: 2},
        {size: :remainder, key: "rest"}
      ].freeze
      FIXED = "Jack      xx12345  123.45tail one\n" \
              "Jill      xx00042000001.5\n" \
              "Bob         0000700000000  spaced  \n".freeze

      SYMBOL_LAYOUT = [{size: 10, key: :name}, {size: 5, key: :zip, type: :integer}].freeze
      STRING_LAYOUT = [{size: 10, key: "name"}, {size: 5, key: "zip"}].freeze
      SYMBOL_FIXED  = "Jack      12345\nJill      00042\n".freeze

      ALLOWED = Csv::ALLOWED

      ALL = [
        {id: "C01_psv_default", desc: "format: :psv, empty middle and trailing value",
         input: {format: :psv}, data: PSV, file_name: "x.psv"},
        {id: "C02_psv_allowed_skip", desc: "format: :psv + allowed_columns + skip_unknown",
         input: {format: :psv, allowed_columns: ALLOWED, skip_unknown: true}, data: PSV, file_name: "x.psv"},
        {id: "C03_json_default", desc: "format: :json, keys that need cleansing",
         input: {format: :json}, data: JSON_LINES, file_name: "x.json"},
        {id: "C04_json_allowed_skip_false", desc: "format: :json + allowed_columns (unknown key Extra)",
         input: {format: :json, allowed_columns: ALLOWED}, data: JSON_LINES, file_name: "x.json"},
        {id: "C05_json_allowed_skip_true", desc: "format: :json + allowed_columns + skip_unknown",
         input: {format: :json, allowed_columns: ALLOWED, skip_unknown: true}, data: JSON_LINES, file_name: "x.json"},
        {id: "C06a_json_required_absent", desc: "format: :json + required_columns [missing]",
         input: {format: :json, required_columns: %w[missing]}, data: JSON_LINES, file_name: "x.json"},
        {id: "C06b_json_required_present", desc: "format: :json + required_columns [zip_code]",
         input: {format: :json, required_columns: %w[zip_code]}, data: JSON_LINES, file_name: "x.json"},
        {id: "C07_fixed_format_options", desc: "format: :fixed, format_options layout: filler, :remainder, " \
                                               "integer, float, truncate: false",
         input: {format: :fixed, format_options: {layout: LAYOUT, truncate: false}}, data: FIXED, file_name: "x.txt"},
        {id: "C08_fixed_symbol_keys", desc: "format: :fixed, layout with Symbol keys and types",
         input: {format: :fixed, format_options: {layout: SYMBOL_LAYOUT}}, data: SYMBOL_FIXED, file_name: "x.txt"},
        {id: "C09_auto_csv_allowed", desc: "format: :auto, x.csv, allowed_columns + skip_unknown (file upload)",
         input: {format: :auto, allowed_columns: ALLOWED, skip_unknown: true}, via: :file},
        {id: "C10a_auto_json_allowed", desc: "format: :auto, x.json, allowed_columns + skip_unknown (file upload)",
         input: {format: :auto, allowed_columns: ALLOWED, skip_unknown: true}, data: JSON_LINES, file_name: "x.json",
         via: :file},
        {id: "C10b_auto_json", desc: "format: :auto, x.json, no options",
         input: {format: :auto}, data: JSON_LINES, file_name: "x.json"},
        {id: "C10c_auto_csv", desc: "format: :auto, x.csv, no options",
         input: {format: :auto}},
        {id: "C11_fixed_format_options_columns", desc: "format: :fixed, format_options + input columns [name] (subset)",
         input: {format: :fixed, format_options: {layout: [{size: 10, key: "name"}, {size: 5, key: "zip", type: :integer}]},
                 columns: %w[name]},
         data: SYMBOL_FIXED, file_name: "x.txt"},
        {id: "C12_fixed_format_options_skip_unknown", desc: "format: :fixed, format_options + skip_unknown: true",
         input: {format: :fixed, format_options: {layout: STRING_LAYOUT}, skip_unknown: true},
         data: SYMBOL_FIXED, file_name: "x.txt"},
        {id: "C13_fixed_short_line", desc: "format: :fixed, format_options, a line shorter than the layout",
         input: {format: :fixed, format_options: {layout: STRING_LAYOUT}},
         data: "Jack      12345\nJill  1\n", file_name: "x.txt"},
        {id: "C14_fixed_blank_integer", desc: "format: :fixed, integer column of spaces",
         input: {format: :fixed, format_options: {layout: [{size: 10, key: "name"}, {size: 5, key: "zip", type: :integer}]}},
         data: "Jack           \n", file_name: "x.txt"},
        {id: "C15_csv_quoting", desc: "format: :csv, quoted values, embedded comma, empty quoted value, spaces",
         input: {format: :csv},
         data: %(name,note,zip\n"Jack","Jones, Jr.",""\n Jill ,"x""y",54321\n"Al",,\n)},
        {id: "C16_csv_blank_and_duplicate_header", desc: "format: :csv, a blank header column, and two that cleanse alike",
         input: {format: :csv}, data: "Name,,Zip Code,zip_code\nJack,x,12345,99999\n"},
        {id: "C17_csv_ragged_rows", desc: "format: :csv, a row with more values, and one with fewer, than the header",
         input: {format: :csv}, data: "name,zip\nJack,12345,extra\nJill\n"},
        {id: "C18_csv_ragged_rows_allowed", desc: "format: :csv + allowed + skip_unknown, ragged rows",
         input: {format: :csv, allowed_columns: %w[name], skip_unknown: true}, data: "name,zip\nJack,12345,extra\nJill\n"},
        {id: "C19_csv_bom_header_allowed", desc: "format: :csv, UTF-8 byte order mark before the header, allowed_columns",
         input: {format: :csv, allowed_columns: ALLOWED, skip_unknown: true}, data: "﻿#{Csv::DATA}"},
        {id: "C20_csv_non_ascii_header_allowed_skip", desc: "format: :csv, header Prénom, allowed [prnom zip_code] + skip_unknown",
         input: {format: :csv, allowed_columns: %w[prnom zip_code], skip_unknown: true},
         data: "Prénom,Zip Code\nJosé,12345\n"},
        {id: "C21_csv_nbsp_header", desc: "format: :csv, header with a no-break space: First Name",
         input: {format: :csv}, data: "First Name,Zip Code\nJack,12345\n"}
      ].freeze
    end
  end
end

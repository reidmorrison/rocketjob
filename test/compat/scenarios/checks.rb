module Compat
  module Scenarios
    # Scenario 11, the property checks: sets of category properties, as a Dirmon entry or an UploadFileJob holds them,
    # with the deprecated column options and format_options, see Compat::Checks.
    module Checks
      LAYOUT = Other::LAYOUT_PROPERTIES

      CASES = {
        "input allowed_columns, required_columns, skip_unknown, header_cleanser" => {
          "input_categories" => [{"name" => "main", "format" => "csv", "allowed_columns" => Csv::ALLOWED,
                                  "required_columns" => %w[zip_code], "skip_unknown" => true, "header_cleanser" => "none"}]
        },
        "input headerless columns"                                               => {
          "input_categories" => [{"name" => "main", "format" => "csv", "columns" => %w[name zip]}]
        },
        "output columns"                                                         => {
          "output_categories" => [{"name" => "main", "format" => "csv", "columns" => %w[b a]}]
        },
        "input format_options"                                                   => {
          "input_categories" => [{"name" => "main", "format" => "fixed", "format_options" => LAYOUT}]
        },
        "input format_options with Symbol keys"                                  => {
          "input_categories" => [{name: "main", format: "fixed", format_options: {layout: Formats::STRING_LAYOUT}}]
        },
        "output format_options"                                                  => {
          "output_categories" => [{"name" => "main", "format" => "fixed", "format_options" => LAYOUT}]
        },
        "output format_options + columns"                                        => {
          "output_categories" => [{"name" => "main", "format" => "fixed", "format_options" => LAYOUT,
                                   "columns" => %w[name zip]}]
        },
        "input format_options + skip_unknown"                                    => {
          "input_categories" => [{"name" => "main", "format" => "fixed", "format_options" => LAYOUT, "skip_unknown" => true}]
        },
        "input format_options, invalid layout (no size)"                         => {
          "input_categories" => [{"name" => "main", "format" => "fixed", "format_options" => {"layout" => [{"key" => "x"}]}}]
        },
        "input format_options for csv"                                           => {
          "input_categories" => [{"name" => "main", "format" => "csv", "format_options" => LAYOUT}]
        }
      }.freeze
    end
  end
end

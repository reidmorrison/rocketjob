require_relative "scenarios/csv"
require_relative "scenarios/formats"
require_relative "scenarios/outputs"
require_relative "scenarios/other"
require_relative "scenarios/persisted"
require_relative "scenarios/checks"

module Compat
  # The scenarios: pre-schema uses of the column options and format_options of a batch job's categories, never a
  # schema, see the modules below, and what a scenario's definition is when it leaves something out, see DEFAULTS.
  module Scenarios
    # A scenario uploads the CSV file of Csv::DATA as x.csv from a StringIO, and writes JSON output, unless its
    # definition says otherwise.
    DEFAULTS = {data: Csv::DATA, file_name: "x.csv", outputs: [{format: :json}].freeze}.freeze

    # Returns [Array<Compat::Scenario>] the scenarios of the matrix, scenarios 1-11.
    def self.matrix
      build(Csv.all + Formats::ALL + Outputs::ALL + Other.all)
    end

    # Returns [Array<Compat::Scenario>] the scenarios of the supplied definitions, with the defaults filled in.
    def self.build(definitions)
      definitions.map { |definition| Scenario.new(DEFAULTS.merge(definition)) }
    end
  end
end

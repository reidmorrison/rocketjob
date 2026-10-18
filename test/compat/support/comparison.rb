require "json"

module Compat
  # Compares the results of two runs, scenario by scenario: knows which parts of a result matter, see VIEW, which
  # result files each comparison reads, see PAIRS, and how to report the differences, the deprecation warnings of v8,
  # and the outcome of the property checks. Loads nothing but JSON, so that it runs without a bundle.
  class Comparison
    # The result files that each comparison compares, the "before" file first, both in the results directory.
    PAIRS = {
      "matrix"         => %w[v7-matrix.json v8-matrix.json],
      "persist"        => %w[v7-persist-process-v7.json v8-persist-process-v8.json],
      "persist-worker" => %w[v7-persist-worker-v7w.json v8-persist-worker-v8w.json],
      "persist-mixed"  => %w[v7-persist-process-v7.json v7-persist-process-mixed.json]
    }.freeze

    # The comparisons that `all` writes to compare-<name>.txt in the results directory.
    ALL = (PAIRS.keys + %w[checks triage warnings]).freeze

    # The parts of a result that are compared: whether and where it raised, what was uploaded, what #perform
    # received, the state of the job, and what was downloaded.
    VIEW = {
      "error"             => ->(result) { error_line(result["error"]) },
      "upload_return"     => ->(result) { result.dig("upload", "return") },
      "record_count"      => ->(result) { result.dig("upload", "record_count") },
      "columns"           => ->(result) { result.dig("upload", "input_category", "columns") },
      "uploaded_records"  => ->(result) { result["uploaded_records"] },
      "received"          => ->(result) { result["received"] },
      "state"             => ->(result) { result.dig("job", "state") },
      "job_exception"     => ->(result) { result.dig("job", "exception") },
      "slice_errors"      => ->(result) { result.dig("job", "slice_errors") },
      "download"          => ->(result) { downloads(result["download"]) },
      "validation_errors" => ->(result) { result["validation_errors"] }
    }.freeze

    # Returns [String] the step, class and first line of the message of an error, or nil.
    def self.error_line(error)
      return unless error

      "#{error['step']}: #{error['class']}: #{error['message'].to_s.lines.first.to_s.strip[0, 160]}"
    end

    # Returns [Hash] the text of each download, or its error.
    def self.downloads(downloads)
      downloads&.transform_values { |output| output["error"] ? "ERROR #{error_line(output['error'])}" : output["text"] }
    end

    # Returns [String] a value as the report shows it.
    def self.show(value)
      value.is_a?(String) || value.nil? ? value.inspect : JSON.generate(value)
    end

    def initialize(dir)
      @dir = dir
    end

    # Returns [String] the report of the supplied comparison, see PAIRS and ALL, or of `versus`, which compares the
    # v8 matrix of the supplied other results directory with the v8 matrix of this one, such as of another commit.
    def report(name, other = nil)
      case name
      when *PAIRS.keys then differences(*PAIRS.fetch(name).map { |file| results(file) })
      when "versus" then differences(results("v8-matrix.json", other || abort("Name the other results directory")),
                                     results("v8-matrix.json"))
      when "checks" then checks
      when "triage" then triage
      when "warnings" then warnings
      else abort("Unknown comparison: #{name.inspect}, one of: #{(ALL + ['all', 'versus DIR']).join(', ')}")
      end
    end

    private

    def results(file, dir = @dir)
      JSON.parse(File.read(File.join(dir, file))).fetch("results")
    end

    # Returns [Hash] the parts of the result that are compared, see VIEW.
    def view(result)
      VIEW.transform_values { |part| part.call(result) }
    end

    def differences(before, after)
      after_by_id = after.to_h { |result| [result["id"], result] }
      rows        = before.map do |result|
        a     = view(result)
        b     = after_by_id[result["id"]] ? view(after_by_id[result["id"]]) : {}
        diffs = (a.keys | b.keys).reject { |key| a[key] == b[key] }
        [result["id"], result["desc"], diffs.to_h { |key| [key, [a[key], b[key]]] }]
      end
      same = rows.count { |_id, _desc, diffs| diffs.empty? }
      ["#{rows.size} scenarios: #{same} same, #{rows.size - same} different", ""] + rows.flat_map { |row| row_lines(*row) }
    end

    def row_lines(id, desc, diffs)
      lines = ["#{diffs.empty? ? 'SAME' : 'DIFF'}  #{id}  (#{desc})"]
      diffs.each do |key, (before, after)|
        lines.push("    #{key}:", "      v7: #{self.class.show(before)}", "      v8: #{self.class.show(after)}")
      end
      lines
    end

    # The outcome of each property check, v7 then v8.
    def checks
      before = JSON.parse(File.read(File.join(@dir, "v7-checks.json"))).fetch("results")
      after  = JSON.parse(File.read(File.join(@dir, "v8-checks.json"))).fetch("results")
      before.each_key.flat_map do |name|
        keys = before[name].keys | after.fetch(name, {}).keys
        ["== #{name}"] + keys.flat_map do |key|
          ["  #{key} v7: #{self.class.show(before[name][key])}", "  #{key} v8: #{self.class.show(after.dig(name, key))}"]
        end
      end
    end

    # The scenarios of the :array and :hash modes that differ, by whether v7 raised, since v7 could not upload in
    # those modes, see the changelog, so that the differences that matter stand out.
    def triage
      before = results("v7-matrix.json")
      after  = results("v8-matrix.json").to_h { |result| [result["id"], result] }
      before.filter_map do |result|
        other = after[result["id"]]
        next unless result["id"].include?("__") && other && view(result) != view(other)

        "#{triage_kind(result, other)}  #{result['id']}: v7 #{self.class.error_line(result['error']) || 'ok'}; " \
          "v8 #{self.class.error_line(other['error']) || 'ok'}"
      end
    end

    def triage_kind(before, after)
      return "V7-RAISED-V8-OK" if before["error"] && !after["error"]
      return "BOTH-RAISED    " if before["error"]

      "V7-OK          "
    end

    # The deprecation warnings that v8 reported, by scenario, with the file and line that each one names.
    def warnings
      Dir[File.join(@dir, "v8-*.json")].flat_map do |file|
        list = JSON.parse(File.read(file)).fetch("warnings").select { |warning| warning["category"] == "deprecated" }
        next [] if list.empty?

        ["== #{File.basename(file)}"] + list.group_by { |warning| warning["scenario"] }.flat_map do |scenario, group|
          ["  #{scenario}:"] + group.map { |w| [w["where"], short(w["location"]), w["message"]] }.tally.map do |(where, location, message), count|
            "    #{count}x [#{where}] #{location}: #{message}"
          end
        end
      end
    end

    def short(location)
      location.to_s.sub(%r{\A.*/test/compat/}, "compat/").sub(%r{\A.*/(lib/(rocket_job|io_streams)/)}, '\1')
    end
  end
end

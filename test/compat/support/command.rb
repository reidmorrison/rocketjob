module Compat
  # A command of run.rb: knows which environment, and so which database, the command uses, runs it, and writes its
  # results, with the versions that this process loaded and everything that was warned or logged meanwhile, to
  # <results>/<v7|v8>-<command>.json.
  #
  #   matrix [id-regexp]     scenarios 1-11, each version in its own database, see Scenarios.matrix
  #   checks                 the property checks of scenario 11, see Checks
  #   persist-create         (v7) save the jobs of scenario 12 without processing them, see PersistedJobs
  #   persist-process COPY   process a copy of each saved job with #perform_now
  #   persist-worker COPY    process a copy of each saved job the way a server's worker does
  #   persist-touch COPY     (v8) load and save a copy of each saved job, without processing it
  #   drop                   drop the databases of the harness
  class Command
    def initialize(name = nil, argument = nil)
      @name     = name
      @argument = argument
    end

    def run
      return Environment.drop_databases! if @name == "drop"

      Environment.load!(@name.to_s.start_with?("persist") ? "shared" : Environment.label)
      results = execute
      path    = Environment.write(
        "#{Environment.label}-#{file_name}.json",
        {"results" => results, "version" => Environment.versions, "warnings" => Capture.warnings, "logs" => Capture.logs}
      )
      puts "Wrote #{path}"
    end

    private

    def execute
      case @name
      when "matrix"
        matrix
      when "checks"
        Environment.drop_collections!
        Checks.new(Scenarios::Checks::CASES).run
      when "persist-create"
        Environment.drop_collections!
        persisted.create
      when "persist-process"
        persisted.process(copy)
      when "persist-worker"
        persisted.work(copy)
      when "persist-touch"
        persisted.touch(copy)
      else
        abort("Unknown command: #{@name.inspect}, see test/compat/README.md")
      end
    end

    # Runs the scenarios of the matrix whose ids match the argument, or all of them, printing the outcome of each.
    def matrix
      Environment.drop_collections!
      scenarios = Scenarios.matrix
      scenarios = scenarios.select { |scenario| scenario.id.match?(Regexp.new(@argument)) } if @argument
      scenarios.map do |scenario|
        result = Runner.new(scenario).run
        error  = result["error"]
        puts "#{scenario.id}: #{error ? "#{error['step']} #{error['class']}" : 'ok'}"
        result.to_h
      end
    end

    # Returns [String] the name of the results of the command: the command, and for scenario 12 the copy that it
    # processed. A matrix run of some of the scenarios replaces the results of a run of all of them.
    def file_name
      @name.start_with?("persist-") && @name != "persist-create" ? "#{@name}-#{copy}" : @name
    end

    def persisted
      PersistedJobs.new(Scenarios::Persisted.all)
    end

    def copy
      @argument || abort("Name the copy to process, one of: #{PersistedJobs::COPIES.join(', ')}")
    end
  end
end

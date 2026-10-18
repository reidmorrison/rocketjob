module Compat
  # Knows where the harness keeps its files: its own directory, its configuration, and the directory that each run
  # writes its results to. The results go to tmp/compat at the root of the repository, which .gitignore ignores,
  # unless COMPAT_RESULTS names another directory.
  #
  # Loads nothing else, so that compare.rb can use it without a bundle.
  module Paths
    DIR    = File.expand_path("..", __dir__)
    CONFIG = File.join(DIR, "config")

    # Returns [String] the directory of the results.
    def self.results
      File.expand_path(ENV.fetch("COMPAT_RESULTS", File.join(DIR, "..", "..", "tmp", "compat")))
    end

    # Returns [String] the path of the supplied file in the results.
    def self.result(name)
      File.join(results, name)
    end
  end
end

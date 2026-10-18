require "fileutils"
require "json"

module Compat
  # Knows which version of Rocket Job this process loaded, and the databases of the harness, see config/mongoid.yml:
  # v7 and v8, where each version runs the matrix, and shared, where v7 saves the jobs that both versions then
  # process. Loads Rocket Job's configuration for an environment, drops the databases, and writes the results of a
  # command.
  module Environment
    ENVIRONMENTS = %w[v7 v8 shared].freeze

    # Returns [String] the version of Rocket Job that this process loaded: "v7" or "v8".
    def self.label
      RocketJob::VERSION.start_with?("7.") ? "v7" : "v8"
    end

    # Connects to the databases of the supplied environment, logging to a file in the results, and recording the
    # warnings and errors that are logged, see Capture.
    def self.load!(env)
      FileUtils.mkdir_p(Paths.results)
      SemanticLogger.sync!
      SemanticLogger.default_level = :info
      SemanticLogger.add_appender(file_name: Paths.result("#{label}-#{env}.log"), formatter: :default)
      SemanticLogger.add_appender(appender: Capture::Logs.new(level: :warn))

      RocketJob::Config.load!(env, config("mongoid.yml"), config("symmetric-encryption.yml"))
      Mongoid.logger             = SemanticLogger[Mongoid]
      Mongo::Logger.logger       = SemanticLogger[Mongo]
      Mongo::Logger.logger.level = :warn
    end

    # Drops the collections of the current environment's database.
    def self.drop_collections!
      RocketJob::Job.collection.database.collections.each(&:drop)
    end

    # Drops the database of every environment of the harness.
    def self.drop_databases!
      ENVIRONMENTS.each do |env|
        Mongoid::Clients.disconnect
        Mongoid.load!(config("mongoid.yml"), env)
        database = Mongoid::Clients.default.database
        database.drop
        puts "Dropped #{database.name}"
      end
    end

    # Returns [Hash] the versions of what this process loaded, and where Rocket Job and IOStreams were loaded from.
    def self.versions
      {
        "rocketjob"      => RocketJob::VERSION,
        "rocketjob_path" => Gem.loaded_specs["rocketjob"]&.full_gem_path,
        "iostreams"      => IOStreams::VERSION,
        "iostreams_path" => Gem.loaded_specs["iostreams"]&.full_gem_path,
        "mongoid"        => Mongoid::VERSION,
        "ruby"           => RUBY_VERSION
      }
    end

    # Writes the supplied object as JSON to the supplied file in the results.
    def self.write(name, object)
      path = Paths.result(name)
      File.write(path, JSON.pretty_generate(object))
      path
    end

    def self.config(name)
      File.join(Paths::CONFIG, name)
    end
    private_class_method :config
  end
end

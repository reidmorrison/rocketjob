require 'yaml'
module RocketJob
  # Centralized Configuration for Rocket Jobs
  class Config
    include Plugins::Document

    # Returns the single instance of the Rocket Job Configuration for this site
    # in a thread-safe way
    def self.instance
      @instance ||= begin
        first || create
      rescue StandardError
        # In case another process has already created the first document
        first
      end
    end

    # DEPRECATED
    cattr_accessor(:inline_mode) { false }

    store_in collection: 'rocket_job.configs'

    #
    # Servers
    #

    # The maximum number of workers to create on any one server
    field :max_workers, type: Integer, default: 10

    # Number of seconds between heartbeats from a Rocket Job Server process
    field :heartbeat_seconds, type: Integer, default: 15

    #
    # Workers
    #

    # Maximum number of seconds a Worker will wait before checking for new jobs
    field :max_poll_seconds, type: Integer, default: 5

    # Number of seconds between checking for:
    # - Jobs with a higher priority
    # - If the current job has been paused, or aborted
    #
    # Making this interval too short results in too many checks for job status
    # changes instead of focusing on completing the active tasks
    #
    # Note:
    #   Not all job types support pausing in the middle
    field :re_check_seconds, type: Integer, default: 60

    # Configure Mongoid
    def self.load!(environment = 'development', file_name = nil, encryption_file_name = nil)
      config_file = file_name ? Pathname.new(file_name) : Pathname.pwd.join('config/mongoid.yml')

      raise(ArgumentError, "Mongo Configuration file: #{config_file} not found") unless config_file.file?

      logger.debug "Reading Mongo configuration from: #{config_file}"
      Mongoid.load!(config_file, environment)

      # Load Encryption configuration file if present
      return unless defined?(SymmetricEncryption)

      config_file =
        if encryption_file_name
          Pathname.new(encryption_file_name)
        else
          Pathname.pwd.join('config/symmetric-encryption.yml')
        end

      return unless config_file.file?

      logger.debug "Reading SymmetricEncryption configuration from: #{config_file}"
      SymmetricEncryption.load!(config_file.to_s, environment)
    end
  end
end

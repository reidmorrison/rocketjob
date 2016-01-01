# encoding: UTF-8
module RocketJob
  # Centralized Configuration for Rocket Jobs
  class Config
    include Plugins::Document

    # Returns the single instance of the Rocket Job Configuration for this site
    # in a thread-safe way
    def self.instance
      @@instance ||= begin
        first || create
      rescue StandardError
        # In case another process has already created the first document
        first
      end
    end

    # Useful for Testing, not recommended elsewhere
    # By enabling inline_mode jobs will be called in-line using perform_now
    # No worker processes will be created, nor threads created
    cattr_accessor(:inline_mode) { false }

    # @formatter:off
    # The maximum number of worker threads to create on any one worker
    key :max_worker_threads,         Integer, default: 10

    # Number of seconds between heartbeats from Rocket Job Worker processes
    key :heartbeat_seconds,          Integer, default: 15

    # Maximum number of seconds a Worker will wait before checking for new jobs
    key :max_poll_seconds,           Integer, default: 5

    # Number of seconds between checking for:
    # - Jobs with a higher priority
    # - If the current job has been paused, or aborted
    #
    # Making this interval too short results in too many checks for job status
    # changes instead of focusing on completing the active tasks
    #
    # Note:
    #   Not all job types support pausing in the middle
    key :re_check_seconds,           Integer, default: 60

    # @formatter:on

    # Replace the MongoMapper default mongo connection for holding jobs
    def self.mongo_connection=(connection)
      connection(connection)
      Worker.connection(connection)
      Job.connection(connection)
      Config.connection(connection)
      DirmonEntry.connection(connection)

      db_name = connection.db.name
      set_database_name(db_name)
      Worker.set_database_name(db_name)
      Job.set_database_name(db_name)
      Config.set_database_name(db_name)
      DirmonEntry.set_database_name(db_name)
    end

    # Configure MongoMapper
    def self.load!(environment='development', file_name=nil, encryption_file_name=nil)
      config_file = file_name ? Pathname.new(file_name) : Pathname.pwd.join('config/mongo.yml')
      if config_file.file?
        logger.debug "Reading MongoDB configuration from: #{config_file}"
        config = YAML.load(ERB.new(config_file.read).result)
        MongoMapper.setup(config, environment)
      else
        raise(ArgumentError, "Mongo Configuration file: #{config_file.to_s} not found")
      end

      # Load Encryption configuration file if present
      if defined?(SymmetricEncryption)
        config_file = encryption_file_name ? Pathname.new(encryption_file_name) : Pathname.pwd.join('config/symmetric-encryption.yml')
        if config_file.file?
          logger.debug "Reading SymmetricEncryption configuration from: #{config_file}"
          SymmetricEncryption.load!(config_file.to_s, environment)
        end
      end
    end

  end
end

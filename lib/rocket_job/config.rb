require "logger"
require "yaml"
module RocketJob
  # Rocket Job Configuration
  class Config
    include SemanticLogger::Loggable

    # [String] This Rocket Job Server name
    class_attribute :server_name
    self.server_name = "#{SemanticLogger.host}:#{$$}"

    # [Integer] The maximum number of workers to create on any one server
    class_attribute :max_workers
    self.max_workers = 10

    # [Integer] Number of seconds between heartbeats from a Rocket Job Server process
    class_attribute :heartbeat_seconds
    self.heartbeat_seconds = 15.0

    # [Integer] Maximum number of seconds a Worker will wait before checking for new jobs
    class_attribute :max_poll_seconds
    self.max_poll_seconds = 5.0

    # [Integer] Number of seconds between checking for:
    # - Jobs with a higher priority
    # - If the current job has been paused, or aborted
    #
    # Making this interval too short results in too many checks for job status
    # changes instead of focusing on completing the active tasks
    #
    # Notes:
    # - Not all job types support pausing in the middle
    #
    # Default: 60 seconds between checks.
    class_attribute :re_check_seconds
    self.re_check_seconds = 60.0

    # [Regexp] Limit this server to only those job classes that match this regular expression.
    #
    # Note:
    # - Supply a case insensitive Regexp if required.
    # - Only supply include_filter or exclude_filter, not both.
    #
    # Example:
    #   # This server can only work on jobs that include anywhere
    #   # in their names: `DirmonJob` or `WeeklyReportJob`
    #   RocketJob::Config.include_filter = /DirmonJob|WeeklyReportJob/i
    class_attribute :include_filter
    self.include_filter = nil

    # [Regexp] Prevent this server from working on any job classes that match this regular expression.
    #
    # Notes:
    # - Supply a case insensitive Regexp if required.
    # - Only supply include_filter or exclude_filter, not both.
    #
    # Example:
    #   # This server can only work any job except that that include anywhere
    #   # in their names: `DirmonJob` or `WeeklyReportJob`
    #   RocketJob::Config.exclude_filter = /DirmonJob|WeeklyReportJob/i
    class_attribute :exclude_filter
    self.exclude_filter = nil

    # [Hash] Limit this server instance to the supplied mongo query filter.
    #
    # Notes:
    # - Can be supplied together with `include_filter` or `exclude_filter` above.
    #
    # Example:
    #   # This server can only work on jobs with priorities between 1 and 25
    #   RocketJob::Config.where_filter = { "priority" => {"$lte" => 25}}
    class_attribute :where_filter
    self.where_filter = nil

    # Configure Mongoid
    def self.load!(environment = "development", file_name = nil, encryption_file_name = nil)
      config_file = file_name ? Pathname.new(file_name) : Pathname.pwd.join("config/mongoid.yml")

      raise(ArgumentError, "Mongo Configuration file: #{config_file} not found") unless config_file.file?

      logger.debug "Reading Mongo configuration from: #{config_file}"
      ::Mongoid.load!(config_file, environment)

      config_file =
        if encryption_file_name
          Pathname.new(encryption_file_name)
        else
          Pathname.pwd.join("config/symmetric-encryption.yml")
        end

      return unless config_file.file?

      logger.debug "Reading SymmetricEncryption configuration from: #{config_file}"
      SymmetricEncryption.load!(config_file.to_s, environment)
    end

    # Returns [Hash] the where clause built from the filters above:
    #    include_filter, exclude_filter, and where_filter.
    # Returns nil if no filter should be applied.
    def self.filter
      raise(ArgumentError, "Cannot supply both an include_filter and an exclude_filter") if include_filter && exclude_filter

      filter                   = where_filter
      (filter ||= {})["_type"] = include_filter if include_filter
      (filter ||= {})["_type"] = {"$not" => exclude_filter} if exclude_filter
      filter&.dup
    end
  end
end

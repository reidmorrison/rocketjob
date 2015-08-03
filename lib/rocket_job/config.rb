# encoding: UTF-8
require 'sync_attr'
module RocketJob
  # Centralized Configuration for Rocket Jobs
  class Config
    include MongoMapper::Document
    include SyncAttr

    # Prevent data in MongoDB from re-defining the model behavior
    #self.static_keys = true

    # Returns the single instance of the Rocket Job Configuration for this site
    # in a thread-safe way
    sync_cattr_reader(:instance) do
      begin
        first || create
      rescue StandardError
        # In case another process has already created the first document
        first
      end
    end

    # By enabling inline_mode jobs will be called in-line
    # No worker processes will be created, nor threads created
    sync_cattr_accessor(:inline_mode) { false }

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

    # Limit the number of workers per job class per worker
    #    'class_name' / group => 100
    #key :limits, Hash
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

    # Use a separate Mongo connection for the Records and Results
    # Allows the records and results to be stored in a separate Mongo database
    # from the Jobs themselves.
    #
    # It is recommended to set the work_connection to a local Mongo Worker that
    # is not replicated to another data center to prevent flooding the network
    # with replication of data records and results.
    # The jobs themselves can/should be replicated across data centers so that
    # they are never lost.
    def self.mongo_work_connection=(connection)
      @@mongo_work_connection = connection
    end

    # Returns the Mongo connection for the Records and Results
    def self.mongo_work_connection
      @@mongo_work_connection || connection
    end

  end
end

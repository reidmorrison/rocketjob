# encoding: UTF-8
require 'sync_attr'
module RocketJob
  # Centralized Configuration for Rocket Jobs
  class Config
    include MongoMapper::Document
    include SyncAttr

    # Returns the single instance of the Batch Configuration
    # in a thread-safe way
    sync_cattr_reader(:instance) do
      begin
        first || create
      rescue Exception => exc
        # In case another process has already created the first document
        first
      end
    end

    # By enabling test_mode jobs will be called in-line
    # No server processes will be created, nor threads created
    sync_cattr_accessor(:test_mode) { false }

    # The maximum number of worker threads to create on any one server
    key :max_worker_threads,         Integer, default: 10

    # Number of seconds between heartbeats from Batch Server processes
    key :heartbeat_seconds,          Integer, default: 15

    # Maximum number of seconds between checks for new jobs
    key :max_poll_seconds,           Integer, default: 5

    # Limit the number of workers per job class per server
    #    'class_name' / group => 100
    key :limits, Hash

    # Replace the MongoMapper default mongo connection for holding jobs
    def self.mongo_connection=(connection)
      connection(connection)
      BatchJob.connection(connection)
      Server.connection(connection)
      Job.connection(connection)

      db_name = connection.db.name
      set_database_name(db_name)
      BatchJob.set_database_name(db_name)
      Server.set_database_name(db_name)
      Job.set_database_name(db_name)
    end

    # Use a separate Mongo connection for the Records and Results
    # Allows the records and results to be stored in a separate Mongo database
    # from the Jobs themselves.
    #
    # It is recommended to set the work_connection to a local Mongo Server that
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

require "rocket_job/server/model"
require "rocket_job/server/state_machine"

module RocketJob
  # Server
  #
  # On startup a server instance will automatically register itself
  # if not already present
  #
  # Starting a server in the foreground:
  #   - Using a Rails runner:
  #     bin/rocketjob
  #
  # Starting a server in the background:
  #   - Using a Rails runner:
  #     nohup bin/rocketjob --quiet 2>&1 1>output.log &
  #
  # Stopping a server:
  #   - Stop the server via the Web UI
  #   - Send a regular kill signal to make it shutdown once all active work is complete
  #       kill <pid>
  #   - Or, use the following Ruby code:
  #     server = RocketJob::Server.where(name: 'server name').first
  #     server.stop!
  #
  #   Sending the kill signal locally will result in starting the shutdown process
  #   immediately. Via the UI or Ruby code the server can take up to 15 seconds
  #   (the heartbeat interval) to start shutting down.
  class Server
    include Plugins::Document
    include Plugins::StateMachine
    include SemanticLogger::Loggable
    include Server::Model
    include Server::StateMachine
  end
end

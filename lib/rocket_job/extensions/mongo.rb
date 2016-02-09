require 'mongo'

Mongo::Logging
module Mongo
  module Logging

    # Remove annoying message on startup
    def write_logging_startup_message
    end

    # Cleanup output
    def log(level, msg)
      MongoClient.logger.send(level, msg)
    end

    private

    def log_operation(name, payload, duration)
      MongoClient.logger.benchmark_trace(name, duration: (duration * 1000), payload: payload)
    end

  end
end

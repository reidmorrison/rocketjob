require 'mongo/monitoring/command_log_subscriber'

module Mongo
  class Monitoring
    class CommandLogSubscriber
      include SemanticLogger::Loggable
      self.logger.name = 'Mongo'

      def started(event)
        logger.debug("#{prefix(event)} Started", event.command)
      end

      def succeeded(event)
        logger.debug(message: "#{prefix(event)} Succeeded", duration: (event.duration * 1000))
      end

      def failed(event)
        logger.debug(message: "#{prefix(event)} Failed: #{event.message}", duration: (event.duration * 1000))
      end

      def prefix(event)
        "#{event.address.to_s} | #{event.database_name}.#{event.command_name}"
      end
    end
  end
end

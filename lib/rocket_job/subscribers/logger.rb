require 'socket'

module RocketJob
  module Subscribers
    class Logger
      include RocketJob::Subscriber

      def self.host_name
        @host_name ||= Socket.gethostname
      end

      def self.host_name=(host_name)
        @host_name = host_name
      end

      # Change the log level
      #
      # Examples:
      #   # Change the global log level to :trace on all servers.
      #   RocketJob::Subscribers::Logger.publish(:set, level: :trace)
      #
      #   # Change the global log level to :trace on one server.
      #   RocketJob::Subscribers::Logger.publish(:set, level: :trace, host_name: 'server1.company.com')
      #
      #   # Change the global log level to :trace for a specific process id.
      #   RocketJob::Subscribers::Logger.publish(:set, level: :trace, host_name: 'server1.company.com', pid: 34567)
      #
      #   # Change the log level for a specific class to :trace.
      #   RocketJob::Subscribers::Logger.publish(:set, level: :trace, class_name: 'RocketJob::Supervisor')
      def set(level: :info, class_name: nil, host_name: nil, pid: nil)
        return unless for_me?(host_name, pid)

        if class_name
          class_name.constantize.logger.level = level
          logger.info "Changed log level to #{level} for #{class_name}"
        else
          SemanticLogger.default_level = level
          logger.info "Changed global log level to #{level}"
        end
      end

      # Dump all backtraces to the log file.
      #
      # Examples:
      #   # Thread dump on all servers:
      #   RocketJob::Subscribers::Logger.publish(:thread_dump)
      #
      #   # Change the global log level to :trace on one server.
      #   RocketJob::Subscribers::Logger.publish(:thread_dump, host_name: 'server1.company.com')
      #
      #   # Change the global log level to :trace for a specific process id.
      #   RocketJob::Subscribers::Logger.publish(:thread_dump, host_name: 'server1.company.com', pid: 34567)
      def thread_dump(host_name: nil, pid: nil)
        return unless for_me?(host_name, pid)

        Thread.list.each do |thread|
          next if thread == Thread.current

          logger.backtrace(thread: thread)
        end
      end

      private

      def for_me?(host_name, pid)
        return true if host_name.nil? && pid.nil?

        return false if host_name && (host_name != self.class.host_name)
        return false if pid && (pid != $$)

        true
      end
    end
  end
end

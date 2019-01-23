require 'socket'

module RocketJob
  class Supervisor
    module Subscriber
      class Logger
        include RocketJob::Subscriber

        def self.host_name
          @host_name ||= Socket.gethostname
        end

        def self.host_name=(host_name)
          @host_name = host_name
        end

        def level(class_name: nil, level: :info, host_name: nil, pid: nil)
          return unless for_me?(host_name, pid)

          if class_name
            class_name.constantize.logger.level = level
            logger.info "Changed log level to #{level} for #{class_name}"
          else
            SemanticLogger.default_level = level
            logger.info "Changed global log level to #{level}"
          end
        end

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
end

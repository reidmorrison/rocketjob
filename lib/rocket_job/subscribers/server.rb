module RocketJob
  module Subscribers
    class Server
      include RocketJob::Subscriber

      attr_reader :supervisor

      def initialize(supervisor)
        @supervisor = supervisor
      end

      def kill(server_id: nil, name: nil, wait_timeout: 5)
        return unless my_server?(server_id, name)

        supervisor.kill
        logger.info "Killed"
      end

      def pause(server_id: nil, name: nil)
        return unless my_server?(server_id, name)

        supervisor.pause
        logger.info "Paused"
      end

      def refresh(server_id: nil, name: nil)
        return unless my_server?(server_id, name)

        Supervisor.event!
        logger.info "Refreshed"
      end

      def resume(server_id: nil, name: nil)
        return unless my_server?(server_id, name)

        supervisor.resume
        logger.info "Resumed"
      end

      def stop(server_id: nil, name: nil)
        return unless my_server?(server_id, name)

        Supervisor.shutdown!
        logger.info "Shutdown"
      end

      def thread_dump(server_id: nil, name: nil)
        return unless my_server?(server_id, name)

        logger.info "Thread dump"
        supervisor.thread_dump
      end

      private

      def my_server?(server_id, name)
        return true if server_id.nil? && name.nil?
        return true if supervisor.server.name == name

        server_id.to_s == supervisor.server.id.to_s
      end
    end
  end
end

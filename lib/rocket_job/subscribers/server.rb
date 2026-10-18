module RocketJob
  module Subscribers
    # Acts on the server events published to this process, when they name its server, or no server, see
    # RocketJob::Supervisor#server?. The supervisor performs each one.
    class Server
      include RocketJob::Subscriber

      attr_reader :supervisor

      def initialize(supervisor)
        @supervisor = supervisor
      end

      def kill(server_id: nil, name: nil, wait_timeout: 5)
        return unless supervisor.server?(server_id: server_id, name: name)

        supervisor.kill(wait_timeout)
        logger.info "Killed"
      end

      def pause(server_id: nil, name: nil)
        return unless supervisor.server?(server_id: server_id, name: name)

        supervisor.pause
        logger.info "Paused"
      end

      def refresh(server_id: nil, name: nil)
        return unless supervisor.server?(server_id: server_id, name: name)

        Supervisor.event!
        logger.info "Refreshed"
      end

      def resume(server_id: nil, name: nil)
        return unless supervisor.server?(server_id: server_id, name: name)

        supervisor.resume
        logger.info "Resumed"
      end

      def stop(server_id: nil, name: nil)
        return unless supervisor.server?(server_id: server_id, name: name)

        Supervisor.shutdown!
        logger.info "Shutdown"
      end

      def thread_dump(server_id: nil, name: nil)
        return unless supervisor.server?(server_id: server_id, name: name)

        logger.info "Thread dump"
        supervisor.log_backtraces
      end
    end
  end
end

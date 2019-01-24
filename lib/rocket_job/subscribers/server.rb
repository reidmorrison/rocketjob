module RocketJob
  module Subscribers
    class Server
      include RocketJob::Subscriber

      attr_reader :supervisor

      def initialize(supervisor)
        @supervisor = supervisor
      end

      def pause(server_id: nil)
        return unless my_server?(server_id)

        supervisor.synchronize { supervisor.server.pause! if supervisor.server.may_pause? }
        Supervisor.event!
        logger.info "Paused"
      end

      def refresh(server_id: nil)
        return unless my_server?(server_id)

        Supervisor.event!
        logger.info "Refreshed"
      end

      def resume(server_id: nil)
        return unless my_server?(server_id)

        supervisor.synchronize { supervisor.server.resume! if supervisor.server.may_resume? }
        Supervisor.event!
        logger.info "Resumed"
      end

      def stop(server_id: nil)
        return unless my_server?(server_id)

        Supervisor.shutdown!
        logger.info "Shutdown"
      end

      def thread_dump(server_id: nil)
        return unless my_server?(server_id)

        logger.info "Thread dump"
        supervisor.worker_pool.log_backtraces
      end

      private

      def my_server?(server_id)
        return true if server_id.nil?

        server_id == supervisor.server.id
      end
    end
  end
end

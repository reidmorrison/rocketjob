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

        supervisor.synchronize do
          Supervisor.shutdown!

          supervisor.logger.info("Stopping Pool")
          supervisor.worker_pool.stop
          unless supervisor.worker_pool.living_count.zero?
            supervisor.logger.info("Giving pool #{wait_timeout} seconds to terminate")
            sleep(wait_timeout)
          end
          supervisor.logger.info("Kill Pool")
          supervisor.worker_pool.kill
        end

        logger.info "Killed"
      end

      def pause(server_id: nil, name: nil)
        return unless my_server?(server_id, name)

        supervisor.synchronize { supervisor.server.pause! if supervisor.server.may_pause? }
        Supervisor.event!
        logger.info "Paused"
      end

      def refresh(server_id: nil, name: nil)
        return unless my_server?(server_id, name)

        Supervisor.event!
        logger.info "Refreshed"
      end

      def resume(server_id: nil, name: nil)
        return unless my_server?(server_id, name)

        supervisor.synchronize { supervisor.server.resume! if supervisor.server.may_resume? }
        Supervisor.event!
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
        supervisor.worker_pool.log_backtraces
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

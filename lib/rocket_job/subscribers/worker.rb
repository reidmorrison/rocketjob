module RocketJob
  module Subscribers
    # Acts on the worker events published to this process, when they name its server, see
    # RocketJob::Supervisor#server?, and one of its workers that is alive, see RocketJob::Supervisor#worker.
    class Worker
      include RocketJob::Subscriber

      attr_reader :supervisor

      def initialize(supervisor)
        @supervisor = supervisor
      end

      def kill(server_id:, worker_id:, wait_timeout: 3)
        worker = locate_worker(server_id, worker_id)
        return unless worker

        worker.shutdown!
        worker.join(wait_timeout)
        worker.kill

        logger.info "Killed"
      end

      def stop(server_id:, worker_id:)
        worker = locate_worker(server_id, worker_id)
        return unless worker

        worker.shutdown!
        logger.info "Stopped Worker: #{worker_id}"
      end

      def thread_dump(server_id:, worker_id:)
        worker = locate_worker(server_id, worker_id)
        return unless worker

        logger.info "Thread dump Worker: #{worker_id}"
        logger.backtrace(thread: worker.thread) if worker.thread
      end

      private

      # Returns the named worker of this server, or nil when the event is for another server, or it has no such
      # worker that is alive.
      def locate_worker(server_id, worker_id)
        return unless server_id && supervisor.server?(server_id: server_id)

        supervisor.worker(worker_id)
      end
    end
  end
end

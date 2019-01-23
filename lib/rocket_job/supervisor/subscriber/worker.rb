module RocketJob
  class Supervisor
    module Subscriber
      class Worker
        include RocketJob::Subscriber

        attr_reader :supervisor

        def initialize(supervisor)
          @supervisor = supervisor
        end

        def stop(server_id:, worker_id:)
          return unless my_server?(server_id)

          worker = locate_worker(worker_id)
          return unless worker

          worker.stop
          logger.info "Stopped"
        end

        def thread_dump(server_id:, worker_id:)
          return unless my_server?(server_id)

          worker = locate_worker(worker_id)
          return unless worker

          logger.info "Thread dump"
          logger.backtrace(thread: worker.thread) if worker.thread && worker.alive?
        end

        private

        def my_server?(server_id)
          server_id == supervisor.server.id
        end

        def locate_worker(worker_id)
          return unless worker_id

          worker = supervisor.worker_pool.find(worker_id)
          return unless worker&.alive?

          worker
        end
      end
    end
  end
end

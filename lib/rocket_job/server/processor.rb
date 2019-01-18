require 'active_support/concern'

module RocketJob
  class Server
    # State machine for sliced jobs
    module Processor
      extend ActiveSupport::Concern

      included do
      end

      private

      # Returns [Array<Worker>] collection of workers
      def workers
        @workers ||= []
      end

      # Management Thread
      def run
        logger.info "Using MongoDB Database: #{RocketJob::Job.collection.database.name}"
        logger.info('Running with filter', filter) if filter
        build_heartbeat(updated_at: Time.now, workers: 0)
        started!
        logger.info 'Rocket Job Server started'

        run_workers

        logger.info 'Waiting for workers to stop'
        # Tell each worker to shutdown cleanly
        workers.each(&:shutdown!)

        while (worker = workers.first)
          if worker.join(5)
            # Worker thread is dead
            workers.shift
          else
            # Timeout waiting for worker to stop
            find_and_update(
              'heartbeat.updated_at' => Time.now,
              'heartbeat.workers'    => worker_count
            )
          end
        end

        logger.info 'Shutdown'
      rescue ::Mongoid::Errors::DocumentNotFound
        logger.warn('Server has been destroyed. Going down hard!')
      rescue Exception => exc
        logger.error('RocketJob::Server is stopping due to an exception', exc)
      ensure
        # Logs the backtrace for each running worker
        workers.each { |worker| logger.backtrace(thread: worker.thread) if worker.thread && worker.alive? }
      end

      def run_workers
        stagger = true
        while running? || paused?
          SemanticLogger.silence(:info) do
            find_and_update(
              'heartbeat.updated_at' => Time.now,
              'heartbeat.workers'    => worker_count
            )
          end
          if paused?
            workers.each(&:shutdown!)
            stagger = true
          end

          # In case number of threads has been modified
          adjust_workers(stagger)
          stagger = false

          # Stop server if shutdown indicator was set
          if self.class.shutdown? && may_stop?
            stop!
          else
            sleep Config.instance.heartbeat_seconds
          end
        end
      end

      # Returns [Fixnum] number of workers (threads) that are alive
      def worker_count
        workers.count(&:alive?)
      end

      def next_worker_id
        @worker_id ||= 0
        @worker_id += 1
      end

      # Re-adjust the number of running workers to get it up to the
      # required number of workers
      #   Parameters
      #     stagger_workers
      #       Whether to stagger when the workers poll for work the first time
      #       It spreads out the queue polling over the max_poll_seconds so
      #       that not all workers poll at the same time
      #       The worker also respond faster than max_poll_seconds when a new
      #       job is added.
      def adjust_workers(stagger_workers = false)
        count = worker_count
        # Cleanup workers that have stopped
        if count != workers.count
          logger.info "Cleaning up #{workers.count - count} workers that went away"
          workers.delete_if { |t| !t.alive? }
        end

        return unless running?

        # Need to add more workers?
        return unless count < max_workers

        worker_count = max_workers - count
        logger.info "Starting #{worker_count} workers"
        worker_count.times.each do
          sleep(Config.instance.max_poll_seconds.to_f / max_workers) if stagger_workers
          return if shutdown?
          # Start worker
          begin
            workers << Worker.new(id: next_worker_id, server_name: name, filter: filter)
          rescue Exception => exc
            logger.fatal('Cannot start worker', exc)
          end
        end
      end

    end
  end
end

require 'active_support/concern'

# Worker behavior for a job
module RocketJob
  module Plugins
    module Job
      module Worker
        extend ActiveSupport::Concern

        module ClassMethods
          # Run this job now.
          #
          # The job is not saved to the database since it is processed entirely in memory
          # As a result before_save and before_destroy callbacks will not be called.
          # Validations are still called however prior to calling #perform
          #
          # Note:
          # - Only batch throttles are checked when perform_now is called.
          def perform_now(args)
            job = new(args)
            yield(job) if block_given?
            job.perform_now
            job
          end

          # Returns the next job to work on in priority based order
          # Returns nil if there are currently no queued jobs, or processing batch jobs
          #   with records that require processing
          #
          # Parameters
          #   worker_name [String]
          #     Name of the worker that will be processing this job
          #
          #   skip_job_ids [Array<BSON::ObjectId>]
          #     Job ids to exclude when looking for the next job
          #
          # Note:
          #   If a job is in queued state it will be started
          def rocket_job_next_job(worker_name, filter = {})
            while (job = rocket_job_retrieve(worker_name, filter))
              if job.running?
                # Batch Job
                return job
              elsif job.expired?
                job.rocket_job_fail_on_exception!(worker_name) { job.destroy }
                logger.info "Destroyed expired job #{job.class.name}, id:#{job.id}"
              elsif (new_filter = job.send(:rocket_job_evaluate_throttles))
                rocket_job_merge_filter(filter, new_filter)
                # Restore retrieved job so that other workers can process it later
                job.set(worker_name: nil, state: :queued)
              else
                job.worker_name = worker_name
                job.rocket_job_fail_on_exception!(worker_name) do
                  defined?(RocketJobPro) ? job.start! : job.start
                end
                return job if job.running?
              end
            end
          end

          # Requeues all jobs that were running on a server that died
          def requeue_dead_server(server_name)
            # Need to requeue paused, failed since user may have transitioned job before it finished
            where(:state.in => %i[running paused failed]).each do |job|
              job.requeue!(server_name) if job.may_requeue?(server_name)
            end
          end

          # DEPRECATED
          def perform_later(args, &block)
            if RocketJob::Config.inline_mode
              perform_now(args, &block)
            else
              job = new(args)
              yield(job) if block
              job.save!
              job
            end
          end

          private

          def rocket_job_merge_filter(target, source)
            source.each_pair do |k, v|
              target[k] =
                if (previous = target[k])
                  v.is_a?(Array) ? previous + v : v
                else
                  v
                end
            end
            target
          end
        end

        # Runs the job now in the current thread.
        #
        # Validations are called prior to running the job.
        #
        # The job is not saved and therefore the following callbacks are _not_ called:
        # * before_save
        # * after_save
        # * before_create
        # * after_create
        #
        # Exceptions are _not_ suppressed and should be handled by the caller.
        def perform_now
          raise(Mongoid::Errors::Validations, self) unless valid?

          worker = RocketJob::Worker.new(inline: true)
          start if may_start?
          # Re-Raise exceptions
          rocket_job_work(worker, true) if running?
          result
        end

        def perform(*)
          raise NotImplementedError
        end

        # Fail this job in the event of an exception.
        #
        # The job is automatically saved only if an exception is raised in the supplied block.
        #
        # worker_name: [String]
        #   Name of the server on which the exception has occurred
        #
        # re_raise_exceptions: [true|false]
        #   Re-raise the exception after updating the job
        #   Default: false
        def rocket_job_fail_on_exception!(worker_name, re_raise_exceptions = false)
          yield
        rescue Exception => exc
          if failed? || !may_fail?
            self.exception        = JobException.from_exception(exc)
            exception.worker_name = worker_name
            save! unless new_record? || destroyed?
          elsif new_record? || destroyed?
            fail(worker_name, exc)
          else
            fail!(worker_name, exc)
          end
          raise exc if re_raise_exceptions
        end

        # Works on this job
        #
        # Returns [true|false] whether this job should be excluded from the next lookup
        #
        # If an exception is thrown the job is marked as failed and the exception
        # is set in the job itself.
        #
        # Thread-safe, can be called by multiple threads at the same time
        def rocket_job_work(worker, re_raise_exceptions = false, _filter = nil)
          raise(ArgumentError, 'Job must be started before calling #rocket_job_work') unless running?
          rocket_job_fail_on_exception!(worker.name, re_raise_exceptions) do
            if _perform_callbacks.empty?
              @rocket_job_output = perform
            else
              # Allows @rocket_job_output to be modified by after/around callbacks
              run_callbacks(:perform) do
                # Allow callbacks to fail, complete or abort the job
                @rocket_job_output = perform if running?
              end
            end

            if collect_output?
              # Result must be a Hash, if not put it in a Hash
              self.result = @rocket_job_output.is_a?(Hash) ? @rocket_job_output : {'result' => @rocket_job_output}
            end

            if new_record? || destroyed?
              complete if may_complete?
            else
              may_complete? ? complete! : save!
            end
          end
          false
        end

        # Returns [Hash<String:[Array<ActiveWorker>]>] All servers actively working on this job
        def rocket_job_active_workers(server_name = nil)
          return [] if !running? || (server_name && !worker_on_server?(server_name))
          [ActiveWorker.new(worker_name, started_at, self)]
        end
      end
    end
  end
end

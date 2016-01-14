# encoding: UTF-8
require 'active_support/concern'

# Worker behavior for a job
module RocketJob
  module Plugins
    module Job
      module Worker
        extend ActiveSupport::Concern

        included do
          # Run this job later
          #
          # Saves it to the database for processing later by workers
          def self.perform_later(*args, &block)
            if RocketJob::Config.inline_mode
              perform_now(*args, &block)
            else
              job = new(arguments: args)
              block.call(job) if block
              job.save!
              job
            end
          end

          # Run this job now.
          #
          # The job is not saved to the database since it is processed entriely in memory
          # As a result before_save and before_destroy callbacks will not be called.
          # Validations are still called however prior to calling #perform
          def self.perform_now(*args, &block)
            job = new(arguments: args)
            block.call(job) if block
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
          def self.rocket_job_next_job(worker_name, skip_job_ids = nil)
            while (job = rocket_job_retrieve(worker_name, skip_job_ids))
              case
              when job.running?
                # Batch Job
                return job
              when job.expired?
                job.rocket_job_fail_on_exception!(worker_name) { job.destroy }
                logger.info "Destroyed expired job #{job.class.name}, id:#{job.id}"
              else
                job.worker_name = worker_name
                job.rocket_job_fail_on_exception!(worker_name) { job.start }
                return job if job.running?
              end
            end
          end

          # Requeues all jobs that were running on worker that died
          def self.requeue_dead_worker(worker_name)
            running.each { |job| job.requeue!(worker_name) if job.may_requeue?(worker_name) }
          end

          # Turn off embedded callbacks. Slow and not used for Jobs
          embedded_callbacks_off
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
          # Call validations
          if respond_to?(:validate!)
            validate!
          elsif invalid?
            raise(MongoMapper::DocumentNotValid, self)
          end
          worker = RocketJob::Worker.new(name: 'inline')
          worker.started
          start if may_start?
          # Raise exceptions
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
        #   Name of the worker on which the exception has occurred
        #
        # raise_exceptions: [true|false]
        #   Re-raise the exception after updating the job
        #   Default: !RocketJob::Config.inline_mode
        def rocket_job_fail_on_exception!(worker_name, raise_exceptions = !RocketJob::Config.inline_mode)
          yield
        rescue Exception => exc
          if failed? || !may_fail?
            self.exception        = JobException.from_exception(exc)
            exception.worker_name = worker_name
          else
            fail(worker_name, exc)
          end
          save! unless new_record?
          raise exc if raise_exceptions
        end

        private

        # Works on this job
        #
        # Returns [true|false] whether this job should be excluded from the next lookup
        #
        # If an exception is thrown the job is marked as failed and the exception
        # is set in the job itself.
        #
        # Thread-safe, can be called by multiple threads at the same time
        def rocket_job_work(worker, raise_exceptions = !RocketJob::Config.inline_mode)
          raise(ArgumentError, 'Job must be started before calling #rocket_job_work') unless running?
          rocket_job_fail_on_exception!(worker.name, raise_exceptions) do
            run_callbacks :perform do
              # Allow callbacks to fail, complete or abort the job
              if running?
                ret = perform(*arguments)
                if collect_output?
                  # Result must be a Hash, if not put it in a Hash
                  self.result = (ret.is_a?(Hash) || ret.is_a?(BSON::OrderedHash)) ? ret : {result: ret}
                end
              end
            end
            complete if may_complete?
            save! unless new_record? || destroyed?
          end
          false
        end

      end
    end
  end
end

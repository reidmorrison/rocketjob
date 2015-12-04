# encoding: UTF-8
require 'active_support/concern'

# Worker behavior for a job
module RocketJob
  module Concerns
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
        def self.next_job(worker_name, skip_job_ids = nil)
          while (job = rocket_job_retrieve(worker_name, skip_job_ids))
            case
            when job.running?
              return job
            when job.expired?
              job.destroy
              logger.info "Destroyed expired job #{job.class.name}, id:#{job.id}"
            else
              job.start
              return job
            end
          end
        end

      end

      # Works on this job
      #
      # Returns [true|false] whether this job should be excluded from the next lookup
      #
      # If an exception is thrown the job is marked as failed and the exception
      # is set in the job itself.
      #
      # Thread-safe, can be called by multiple threads at the same time
      def work(worker, raise_exceptions = !RocketJob::Config.inline_mode)
        raise(ArgumentError, 'Job must be started before calling #work') unless running?
        begin
          run_callbacks :perform do
            ret = perform(*arguments)
            if collect_output?
              # Result must be a Hash, if not put it in a Hash
              self.result = (ret.is_a?(Hash) || ret.is_a?(BSON::OrderedHash)) ? ret : {result: ret}
            end
          end
          new_record? ? complete : complete!
        rescue Exception => exc
          fail(worker.name, exc) if may_fail?
          save! unless new_record?
          raise(exc) if raise_exceptions
        end
        false
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
          raise(MongoMapper::DocumentNotValid, "Validation failed: #{errors.messages.join(', ')}")
        end
        worker = RocketJob::Worker.new(name: 'inline')
        worker.started
        start if may_start?
        work(worker) if running?
        result
      end

      def perform(*)
        fail NotImplementedError
      end

    end
  end
end

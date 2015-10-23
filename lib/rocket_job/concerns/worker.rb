# encoding: UTF-8
require 'active_support/concern'

# Worker behavior for a job
module RocketJob
  module Concerns
    module Worker
      extend ActiveSupport::Concern

      included do
        # Returns [Job] after queue-ing it for processing
        def self.later(method, *args, &block)
          if RocketJob::Config.inline_mode
            now(method, *args, &block)
          else
            job = build(method, *args, &block)
            job.save!
            job
          end
        end

        # Create a job and process it immediately in-line by this thread
        def self.now(method, *args, &block)
          build(method, *args, &block).work_now
        end

        # Build a Rocket Job instance
        #
        # Note:
        #  - #save! must be called on the return job instance if it needs to be
        #    queued for processing.
        #  - If data is uploaded into the job instance before saving, and is then
        #    discarded, call #cleanup! to clear out any partially uploaded data
        def self.build(method, *args, &block)
          job = new(arguments: args, perform_method: method.to_sym)
          block.call(job) if block
          job
        end

        # Method to be performed later
        def self.perform_later(*args, &block)
          later(:perform, *args, &block)
        end

        # Method to be performed later
        def self.perform_build(*args, &block)
          build(:perform, *args, &block)
        end

        # Method to be performed now
        def self.perform_now(*args, &block)
          now(:perform, *args, &block)
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
          query        = {
            '$and' => [
              {
                '$or' => [
                  {'state' => 'queued'}, # Jobs
                  {'state' => 'running', 'sub_state' => :processing} # Slices
                ]
              },
              {
                '$or' => [
                  {run_at: {'$exists' => false}},
                  {run_at: {'$lte' => Time.now}}
                ]
              }
            ]
          }
          query['_id'] = {'$nin' => skip_job_ids} if skip_job_ids && skip_job_ids.size > 0

          while (doc = find_and_modify(
            query:  query,
            sort:   [['priority', 'asc'], ['created_at', 'asc']],
            update: {'$set' => {'worker_name' => worker_name, 'state' => 'running'}}
          ))
            job = load(doc)
            if job.running?
              return job
            else
              if job.expired?
                job.destroy
                logger.info "Destroyed expired job #{job.class.name}, id:#{job.id}"
              else
                # Also update in-memory state and run call-backs
                job.start
                job.set(started_at: job.started_at)
                return job
              end
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
      def work(worker, raise_exceptions = RocketJob::Config.inline_mode)
        raise(ArgumentError, 'Job must be started before calling #work') unless running?
        begin
          # New callbacks mechanism
          callbacks = self.class.rocketjob_callbacks[perform_method]

          # Call before callbacks
          rocketjob_call_callbacks("before_#{perform_method}".to_sym, callbacks.try!(:before_list))

          # Allow before callbacks to explicitly fail this job
          return unless running?

          # Call perform and around block(s) if defined
          ret =
            if callbacks && (callbacks.around_list.size > 0)
              callbacks.exec_around_callbacks(target, *arguments) { call_block(perform_method) }
            else
              call_block(perform_method)
            end
          if self.collect_output?
            self.result = (ret.is_a?(Hash) || ret.is_a?(BSON::OrderedHash)) ? ret : {result: ret}
          end

          # Only run after perform(s) if perform did not explicitly fail the job
          return unless running?

          # Call after callbacks
          rocketjob_call_callbacks("after_#{perform_method}".to_sym, callbacks.try!(:after_list))

          # Only complete if after callbacks did not fail
          return unless running?

          new_record? ? complete : complete!
        rescue StandardError => exc
          fail(worker.name, exc) if may_fail?
          logger.error("Exception running #{self.class.name}##{perform_method}", exc)
          save! unless new_record?
          raise exc if raise_exceptions
        end
        false
      end

      # Validates and runs the work on this job now in the current thread
      # Returns this job once it has finished running
      # Exceptions will flow though aside from updating the exception in the job itself
      def work_now(raise_exceptions = true)
        # Call validations
        if respond_to?(:validate!)
          validate!
        elsif invalid?
          raise(MongoMapper::DocumentNotValid, "Validation failed: #{errors.messages.join(', ')}")
        end
        worker = RocketJob::Worker.new(name: 'inline')
        worker.started
        start if may_start?
        while running? && !work(worker, raise_exceptions)
        end
        self
      end

      protected

      # Calls a method on this job, if it is defined
      # Adds the event name to the method call if supplied
      #
      # Returns [Object] the result of calling the method
      #
      def call_block(the_method, &block)
        method_name = "#{self.class.name}##{the_method}"
        logger.info "Start #{method_name}"
        logger.benchmark_info(
          "Completed #{method_name}",
          metric:             "rocketjob/#{self.class.name.underscore}/#{the_method}",
          log_exception:      :full,
          on_exception_level: :error,
          silence:            log_level
        ) do
          block ? instance_exec(*arguments, &block) : send(the_method, *arguments)
        end
      end

      # Calls the callbacks for this job

      # Parameters
      #   event: [Symbol]
      #     Any one of: :before, :after
      #     Default: nil, just calls the method itself
      def rocketjob_call_callbacks(the_method, callbacks = nil)
        # DEPRECATED before_perform technique
        call_block(the_method) if respond_to?(the_method)

        if callbacks
          callbacks.each do |block|
            # Allow callback to explicitly fail this job
            return unless running?

            call_block(the_method, &block)
          end
        end
      end

    end
  end
end

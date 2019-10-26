require 'active_support/concern'

module RocketJob
  module Batch
    module Worker
      extend ActiveSupport::Concern

      included do
        # While working on a slice, the current slice is available via this reader
        attr_reader :rocket_job_slice, :rocket_job_record_number

        private

        attr_writer :rocket_job_slice, :rocket_job_record_number
      end

      # Processes records in each available slice for this job. Slices are processed
      # one at a time to allow for concurrent calls to this method to increase
      # throughput. Processing will continue until there are no more jobs available
      # for this job.
      #
      # Returns [true|false] whether this job should be excluded from the next lookup
      #
      # Slices are destroyed after their records are successfully processed
      #
      # Results are stored in the output collection if `collect_output?`
      # `nil` results from workers are kept if `collect_nil_output`
      #
      # If an exception was thrown the entire slice of records is marked as failed.
      #
      # If the mongo_ha gem has been loaded, then the connection to mongo is
      # automatically re-established and the job will resume anytime a
      # Mongo connection failure occurs.
      #
      # Thread-safe, can be called by multiple threads at the same time
      def rocket_job_work(worker, re_raise_exceptions = false, filter = {})
        raise 'Job must be started before calling #rocket_job_work' unless running?
        start_time = Time.now
        if sub_state != :processing
          rocket_job_handle_callbacks(worker, re_raise_exceptions)
          return false unless running?
        end

        while !worker.shutdown?
          if slice = input.next_slice(worker.name)
            # Grab a slice before checking the throttle to reduce concurrency race condition.
            if new_filter = rocket_job_batch_evaluate_throttles(slice)
              # Restore retrieved slice so that other workers can process it later.
              slice.set(worker_name: nil, state: :queued, started_at: nil)
              self.class.send(:rocket_job_merge_filter, filter, new_filter)
              return true
            end

            SemanticLogger.named_tagged(slice: slice.id.to_s) do
              rocket_job_process_slice(slice, re_raise_exceptions)
            end
          else
            break if record_count && rocket_job_batch_complete?(worker.name)
            logger.debug 'No more work available for this job'
            self.class.send(:rocket_job_merge_filter, filter, throttle_filter_id)
            return true
          end

          # Allow new jobs with a higher priority to interrupt this job
          break if (Time.now - start_time) >= Config.re_check_seconds
        end
        false
      end

      # Prior to a job being made available for processing it can be processed one
      # slice at a time.
      #
      # For example, to extract the header row which would be in the first slice.
      #
      # Returns [Integer] the number of records processed in the slice
      #
      # Note: The slice will be removed from processing when this method completes
      def work_first_slice(&block)
        raise '#work_first_slice can only be called from within before_batch callbacks' unless sub_state == :before
        # TODO Make these settings configurable
        count        = 0
        wait_seconds = 5
        while (slice = input.first).nil?
          break if count > 10
          logger.info "First slice has not arrived yet, sleeping for #{wait_seconds} seconds"
          sleep wait_seconds
          count += 1
        end

        if slice = input.first
          SemanticLogger.named_tagged(slice: slice.id.to_s) do
            # TODO Persist that the first slice is being processed by this worker
            slice.start
            rocket_job_process_slice(slice, true, &block)
          end
        else
          # No records processed
          0
        end
      end

      # Returns [Array<ActiveWorker>] All workers actively working on this job
      def rocket_job_active_workers(server_name = nil)
        servers = []
        case sub_state
        when :before, :after
          unless server_name && !worker_on_server?(server_name)
            servers << ActiveWorker.new(worker_name, started_at, self) if running?
          end
        when :processing
          query = input.running
          query = query.where(worker_name: /\A#{server_name}/) if server_name
          query.each do |slice|
            servers << ActiveWorker.new(slice.worker_name, slice.started_at, self)
          end
        end
        servers
      end

      private

      # Process a single slice from Mongo
      # Once the slice has been successfully processed it will be removed from the input collection
      # Returns [Integer] the number of records successfully processed
      def rocket_job_process_slice(slice, re_raise_exceptions)
        slice_record_number       = 0
        @rocket_job_record_number = slice.first_record_number || 0
        @rocket_job_slice         = slice
        run_callbacks :slice do
          RocketJob::Sliced::Writer::Output.collect(self, slice) do |writer|
            slice.each do |record|
              slice_record_number += 1
              SemanticLogger.named_tagged(record: @rocket_job_record_number) do
                if _perform_callbacks.empty?
                  @rocket_job_output = block_given? ? yield(record) : perform(record)
                else
                  # Allows @rocket_job_input to be modified by before/around callbacks
                  @rocket_job_input = record
                  # Allow callbacks to fail, complete or abort the job
                  if running?
                    if block_given?
                      run_callbacks(:perform) { @rocket_job_output = yield(@rocket_job_input) }
                    else
                      # Allows @rocket_job_output to be modified by after/around callbacks
                      run_callbacks(:perform) { @rocket_job_output = perform(@rocket_job_input) }
                    end
                  end
                end
                writer << @rocket_job_output
              end
              # JRuby says self.rocket_job_record_number= is private and cannot be accessed
              @rocket_job_record_number += 1
            end
          end
          @rocket_job_input = @rocket_job_slice = @rocket_job_output = nil
        end

        # On successful completion remove the slice from the input queue
        # TODO Option to complete slice instead of destroying it to retain input data
        slice.destroy
        slice_record_number
      rescue Exception => exc
        slice.fail!(exc, slice_record_number)
        raise exc if re_raise_exceptions
        slice_record_number > 0 ? slice_record_number - 1 : 0
      end

      # Checks for completion and runs after_batch if defined
      # Returns true if the job is now complete/aborted/failed
      def rocket_job_batch_complete?(worker_name)
        return true unless running?
        return false unless record_count

        # Only failed slices left?
        input_count  = input.count
        failed_count = input.failed.count
        if (failed_count > 0) && (input_count == failed_count)
          # Reload to pull in any counters or other data that was modified.
          reload unless new_record?
          if may_fail?
            fail_job = true
            unless new_record?
              # Fail job iff no other worker has already finished it
              # Must set write concern to at least 1 since we need the nModified back
              result   = self.class.with(write: {w: 1}) do |query|
                query.
                  where(id: id, state: :running, sub_state: :processing).
                  update({'$set' => {state: :failed, worker_name: worker_name}})
              end
              fail_job = false unless result.modified_count > 0
            end
            if fail_job
              message        = "#{failed_count} slices failed to process"
              self.exception = JobException.new(message: message)
              fail!(worker_name, message)
            end
          end
          return true
        end

        # Any work left?
        return false if input_count > 0

        # If the job was not saved to the queue, do not save any changes
        if new_record?
          rocket_job_batch_run_after_callbacks(false)
          return true
        end

        # Complete job iff no other worker has already completed it
        # Must set write concern to at least 1 since we need the nModified back
        result = self.class.with(write: {w: 1}) do |query|
          query.
            where(id: id, state: :running, sub_state: :processing).
            update('$set' => {sub_state: :after, worker_name: worker_name})
        end

        # Reload to pull in any counters or other data that was modified.
        reload
        if result.modified_count > 0
          rocket_job_batch_run_after_callbacks(false)
        else
          # Repeat cleanup in case this worker was still running when the job was aborted
          cleanup! if aborted?
        end
        true
      end

      # Run the before_batch callbacks
      # Saves the current state before and after running callbacks if callbacks present
      def rocket_job_batch_run_before_callbacks
        unless _before_batch_callbacks.empty?
          self.sub_state = :before
          save! unless new_record? || destroyed?
          logger.measure_info(
            'before_batch',
            metric:             "#{self.class.name}/before_batch",
            log_exception:      :full,
            on_exception_level: :error,
            silence:            log_level
          ) do
            run_callbacks(:before_batch)
          end
        end
        self.sub_state = :processing
        save! unless new_record? || destroyed?
      end

      # Run the after_batch callbacks
      # Saves the current state before and after running callbacks if callbacks present
      def rocket_job_batch_run_after_callbacks(save_before = true)
        unless _after_batch_callbacks.empty?
          self.sub_state = :after
          save! if save_before && !new_record? && !destroyed?
          logger.measure_info(
            'after_batch',
            metric:             "#{self.class.name}/after_batch",
            log_exception:      :full,
            on_exception_level: :error,
            silence:            log_level
          ) do
            run_callbacks(:after_batch)
          end
        end
        if new_record? || destroyed?
          complete if may_complete?
        else
          may_complete? ? complete! : save!
        end
      end

      # Handle before and after callbacks
      def rocket_job_handle_callbacks(worker, re_raise_exceptions)
        rocket_job_fail_on_exception!(worker.name, re_raise_exceptions) do
          # If this is the first worker to pickup this job
          if sub_state == :before
            rocket_job_batch_run_before_callbacks
            # Check for 0 record jobs
            rocket_job_batch_complete?(worker.name) if running?
          elsif sub_state == :after
            rocket_job_batch_run_after_callbacks
          end
        end
      end

    end
  end
end

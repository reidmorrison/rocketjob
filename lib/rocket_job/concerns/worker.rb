# encoding: UTF-8

# Mix-in to add Worker behavior to a class
module RocketJob
  module Concerns
    module Worker
      def self.included(base)
        base.extend ClassMethods
        base.class_eval do
          # While working on a slice, the current slice is available via this reader
          attr_reader :rocket_job_slice

          @rocket_job_defaults = nil
        end
      end

      module ClassMethods
        # Returns [Job] after queue-ing it for processing
        def later(method, *args, &block)
          if RocketJob::Config.inline_mode
            now(method, *args, &block)
          else
            job = build(method, *args, &block)
            job.save!
            job
          end
        end

        # Create a job and process it immediately in-line by this thread
        def now(method, *args, &block)
          job = build(method, *args, &block)
          server = Server.new(name: 'inline')
          server.started
          job.start
          while job.running?
            job.work(server)
          end
          job
        end

        # Build a Rocket Job instance that can be used to call a specific
        # method as a rocket job worker
        #
        # Note:
        #  - #save! must be called on the return job instance if it needs to be
        #    queued for processing.
        #  - If data is uploaded into the job instance before saving, and is then
        #    discarded, call #cleanup! to clear out any partially uploaded data
        def build(method, *args, &block)
          job = new(arguments: args, perform_method: method.to_sym)
          @rocket_job_defaults.call(job) if @rocket_job_defaults
          block.call(job) if block
          job
        end

        # Method to be performed later
        def perform_later(*args, &block)
          later(:perform, *args, &block)
        end

        # Method to be performed later
        def perform_build(*args, &block)
          build(:perform, *args, &block)
        end

        # Method to be performed now
        def perform_now(*args, &block)
          now(:perform, *args, &block)
        end

        # Define job defaults
        def rocket_job(&block)
          @rocket_job_defaults = block
          self
        end

        # Returns the job class
        def rocket_job_class
          @rocket_job_class
        end
      end

      def rocket_job_csv_parser
        # TODO Change into an instance variable once CSV handling has been re-worked
        RocketJob::Utility::CSVRow.new
      end

      # Invokes the worker to process this job
      #
      # Returns [true|false] whether this job should be excluded from the next lookup
      #
      # If an exception is thrown the job is marked as failed and the exception
      # is set in the job itself.
      #
      # Thread-safe, can be called by multiple threads at the same time
      def work(server)
        raise 'Job must be started before calling #work' unless running?
        begin
          # before_perform
          rocket_job_call(perform_method, arguments, event: :before, log_level: log_level)

          # perform
          rocket_job_call(perform_method, arguments, log_level: log_level)
          if self.collect_output?
            self.output = (result.is_a?(Hash) || result.is_a?(BSON::OrderedHash)) ? result : { result: result }
          end

          # after_perform
          rocket_job_call(perform_method, arguments, event: :after, log_level: log_level)
          complete!
        rescue Exception => exc
          set_exception(server.name, exc)
          raise exc if RocketJob::Config.inline_mode
        end
        false
      end

      protected

      # Calls a method on this worker, if it is defined
      # Adds the event name to the method call if supplied
      #
      # Returns [Object] the result of calling the method
      #
      # Parameters
      #   method [Symbol]
      #     The method to call on this worker
      #
      #   arguments [Array]
      #     Arguments to pass to the method call
      #
      #   Options:
      #     event: [Symbol]
      #       Any one of: :before, :after
      #       Default: None, just calls the method itself
      #
      #     log_level: [Symbol]
      #       Log level to apply to silence logging during the call
      #       Default: nil ( no change )
      #
      def rocket_job_call(method, arguments, options={})
        options               = options.dup
        event                 = options.delete(:event)
        log_level             = options.delete(:log_level)
        raise(ArgumentError, "Unknown RocketJob::Worker#rocket_job_call options: #{options.inspect}") if options.size > 0

        the_method = event.nil? ? method : "#{event}_#{method}".to_sym
        if respond_to?(the_method)
          method_name = "#{self.class.name}##{the_method}"
          logger.info "Start #{method_name}"
          logger.benchmark_info("Completed #{method_name}",
            metric:             "rocket_job/#{self.class.name.underscore}/#{the_method}",
            log_exception:      :full,
            on_exception_level: :error,
            silence:            log_level
          ) do
            self.send(the_method, *arguments)
          end
        end
      end

    end
  end
end
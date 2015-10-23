# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Concerns
    # Define before and after callbacks
    #
    # class Job < RocketJob::Job
    #   before_perform do |job|
    #     puts "BEFORE PERFORM1"
    #   end
    #
    #   before_perform do |job|
    #     puts "BEFORE PERFORM2"
    #   end
    #
    #   around_perform do |job, &block|
    #     puts "AROUND BEFORE PERFORM1"
    #     block.call(job)
    #     puts "AROUND AFTER PERFORM1"
    #   end
    #
    #   around_perform do |job, &block|
    #     puts "AROUND BEFORE PERFORM2"
    #     block.call(job)
    #     puts "AROUND AFTER PERFORM2"
    #   end
    #
    #   after_perform do |job|
    #     puts "AFTER PERFORM"
    #   end
    #
    #   after_perform do |job|
    #     puts "AFTER PERFORM2"
    #   end
    #
    #   def perform
    #     puts "PERFORM"
    #     23
    #   end
    # end
    #
    # job = Job.new
    # job.work_now
    #
    # Output from the example above
    #
    #   BEFORE PERFORM2
    #   BEFORE PERFORM1
    #   AROUND BEFORE PERFORM2
    #   AROUND BEFORE PERFORM1
    #   PERFORM
    #   AROUND AFTER PERFORM1
    #   AROUND AFTER PERFORM2
    #   AFTER PERFORM
    #   AFTER PERFORM2
    module Callbacks
      extend ActiveSupport::Concern

      included do
        @rocketjob_callbacks = ThreadSafe::Hash.new

        def self.inherited(subclass)
          super
          subclass.instance_variable_set(:@rocketjob_callbacks, @rocketjob_callbacks.dup)
        end

        def self.before(perform_method, &block)
          rocketjob_callbacks_get(perform_method).before(&block)
        end

        def self.before_perform(&block)
          rocketjob_callbacks_get(:perform).before(&block)
        end

        def self.after(perform_method, &block)
          rocketjob_callbacks_get(perform_method).after(&block)
        end

        def self.after_perform(&block)
          rocketjob_callbacks_get(:perform).after(&block)
        end

        def self.around(perform_method, &block)
          rocketjob_callbacks_get(perform_method).around(&block)
        end

        def self.around_perform(&block)
          rocketjob_callbacks_get(:perform).around(&block)
        end

        def self.rocketjob_callbacks
          @rocketjob_callbacks
        end

        protected

        # Add a new callback
        def self.rocketjob_callbacks_get(perform_method = :perform)
          (@rocketjob_callbacks[perform_method] ||= ::RocketJob::Callbacks.new { |*args| send(perform_method, *args) })
        end
      end

    end
  end
end

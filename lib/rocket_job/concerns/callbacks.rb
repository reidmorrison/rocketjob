# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Concerns
    # Define before and after callbacks
    #
    # Before callbacks are called in the order they are defined.
    # After callbacks are called in the _reverse_ order to which they were defined.
    #
    # Example:
    #    before_1
    #    before_2
    #    perform
    #    after_2
    #    after_1
    #
    # Example including around callbacks:
    #
    # class MyJob < RocketJob::Job
    #   before_perform do
    #     puts "BEFORE 1"
    #   end
    #
    #   around_perform do |job, block|
    #     puts "AROUND 1 BEFORE"
    #     block.call
    #     puts "AROUND 1 AFTER"
    #   end
    #
    #   before_perform do
    #     puts "BEFORE 2"
    #   end
    #
    #   after_perform do
    #     puts "AFTER 1"
    #   end
    #
    #   around_perform do |job, block|
    #     puts "AROUND 2 BEFORE"
    #     block.call
    #     puts "AROUND 2 AFTER"
    #   end
    #
    #   after_perform do
    #     puts "AFTER 2"
    #   end
    #
    #   def perform
    #     puts "PERFORM"
    #     23
    #   end
    # end
    #
    # MyJob.new.perform_now
    #
    # Output from the example above
    #
    #  BEFORE 1
    #  AROUND 1 BEFORE
    #  BEFORE 2
    #  AROUND 2 BEFORE
    #  PERFORM
    #  AFTER 2
    #  AROUND 2 AFTER
    #  AFTER 1
    #  AROUND 1 AFTER
    module Callbacks
      extend ActiveSupport::Concern
      include ActiveSupport::Callbacks

      included do
        define_callbacks :perform

        def self.before_perform(*filters, &blk)
          set_callback(:perform, :before, *filters, &blk)
        end

        def self.after_perform(*filters, &blk)
          set_callback(:perform, :after, *filters, &blk)
        end

        def self.around_perform(*filters, &blk)
          set_callback(:perform, :around, *filters, &blk)
        end

      end

    end
  end
end

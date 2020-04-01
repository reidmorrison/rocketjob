require "active_support/concern"
module RocketJob
  module Batch
    # Automatically lower the priority for Jobs with a higher record_count.
    #
    # Note:
    #   - Add `:lower_priority` as a before_batch, but only once the `record_count` has been set.
    #   - If the `record_count` is not set by the time this plugins `before_batch`
    #     is called, then the priority will not be modified.
    #
    # class SampleJob < RocketJob::Job
    #   include RocketJob::Plugins::Batch
    #   include RocketJob::Plugins::Batch::LowerPriority
    #
    #   before_batch :upload_data, :lower_priority
    #
    #   def perform(record)
    #     record.reverse
    #   end
    #
    #   private
    #
    #   def upload_data
    #     upload do |stream|
    #       stream << 'abc'
    #       stream << 'def'
    #       stream << 'ghi'
    #     end
    #   end
    # end
    module LowerPriority
      extend ActiveSupport::Concern

      included do
        unless public_method_defined?(:record_count=)
          raise(ArgumentError, "LowerPriority can only be used in conjunction with RocketJob::Plugins::Batch")
        end

        # For each of this many records lower the priority by 1.
        class_attribute :lower_priority_count
        self.lower_priority_count = 100_000
      end

      private

      def lower_priority
        return unless record_count

        new_priority  = priority + (record_count.to_f / lower_priority_count).to_i
        self.priority = [new_priority, 100].min
      end
    end
  end
end

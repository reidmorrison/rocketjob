require_relative "../test_helper"

module Batch
  class CallbacksTest < Minitest::Test
    # This job adds each callback as they run into an array
    class BatchSlicesJob < RocketJob::Job
      include RocketJob::Batch

      field :call_list, type: Array, default: []

      before_slice do
        call_list << "before_slice_block"
      end

      after_slice do
        call_list << "after_slice_block"
      end

      around_slice do |_job, block|
        call_list << "around_slice_block_before"
        block.call
        call_list << "around_slice_block_after"
      end

      before_slice :before_slice_method

      around_slice :around_slice_method

      after_slice :after_slice_method

      def perform(record)
        call_list << "perform#{record}"
      end

      private

      def before_slice_method
        call_list << "before_slice_method"
      end

      def around_slice_method
        call_list << "around_slice_method_before"
        yield
        call_list << "around_slice_method_after"
      end

      def after_slice_method
        call_list << "after_slice_method"
      end
    end

    # This job adds each callback as they run into an array
    class BatchCallbacksJob < RocketJob::Job
      include RocketJob::Batch

      field :call_list, type: Array, default: []

      before_batch do
        call_list << "before_batch_block"
      end

      after_batch do
        call_list << "after_batch_block"
      end

      before_batch :before_batch_method
      before_batch :before_batch_method2

      after_batch :after_batch_method
      after_batch :after_batch_method2

      def perform(record)
        call_list << "perform#{record}"
      end

      private

      def before_batch_method
        call_list << "before_batch_method"
      end

      def after_batch_method
        call_list << "after_batch_method"
      end

      def before_batch_method2
        call_list << "before_batch_method2"
      end

      def after_batch_method2
        call_list << "after_batch_method2"
      end
    end

    describe RocketJob::Batch::Callbacks do
      after do
        @job.destroy if @job && !@job.new_record?
      end

      describe "slice callbacks" do
        it "runs them in the right order" do
          records                        = 7
          @job                           = BatchSlicesJob.new
          @job.input_category.slice_size = 5
          @job.upload do |stream|
            records.times.each { |i| stream << i }
          end
          @job.perform_now
          assert @job.completed?, @job.attributes.ai
          performs = records.times.collect { |i| "perform#{i}" }
          befores  = %w[before_slice_block around_slice_block_before before_slice_method around_slice_method_before]
          afters   = %w[after_slice_method around_slice_method_after around_slice_block_after after_slice_block]
          expected = befores + performs[0..4] + afters + befores + performs[5..-1] + afters
          assert_equal expected, @job.call_list, "Sequence of slice callbacks is incorrect"
        end
      end

      describe "batch callbacks" do
        it "runs them in the right order" do
          records                        = 7
          @job                           = BatchCallbacksJob.new
          @job.input_category.slice_size = 5
          @job.upload do |stream|
            records.times.each { |i| stream << i }
          end
          @job.perform_now
          assert @job.completed?, @job.attributes.ai
          performs = records.times.collect { |i| "perform#{i}" }
          befores  = %w[before_batch_block before_batch_method before_batch_method2]
          afters   = %w[after_batch_method2 after_batch_method after_batch_block]
          expected = befores + performs + afters
          assert_equal expected, @job.call_list, "Sequence of batch callbacks is incorrect"
        end
      end
    end
  end
end

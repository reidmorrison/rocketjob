require_relative "../test_helper"

module Batch
  class LowerPriorityTest < Minitest::Test
    class BatchJob < RocketJob::Job
      include RocketJob::Batch
      include RocketJob::Batch::LowerPriority

      self.slice_size = 2

      before_batch :upload_test, :lower_priority

      def perform(record)
        record.reverse
      end

      private

      def upload_test
        upload do |stream|
          stream << "abc"
          stream << "def"
          stream << "ghi"
        end
      end
    end

    describe RocketJob::Batch::LowerPriority do
      describe "#lower_priority" do
        it "no change when record_count nil" do
          job = BatchJob.new
          assert_nil job.record_count
          job.send(:lower_priority)
          assert_equal BatchJob.priority, job.priority
        end

        it "no change when record_count 100" do
          job              = BatchJob.new
          job.record_count = 100
          job.send(:lower_priority)
          assert_equal BatchJob.priority, job.priority
        end

        it "lower by 1 when record_count 100_000" do
          job              = BatchJob.new
          job.record_count = BatchJob.lower_priority_count
          job.send(:lower_priority)
          assert_equal BatchJob.priority + 1, job.priority
        end

        it "lower by 2 when record_count 200_000" do
          job              = BatchJob.new
          job.record_count = 2 * BatchJob.lower_priority_count
          job.send(:lower_priority)
          assert_equal BatchJob.priority + 2, job.priority
        end
      end

      describe "#perform_now" do
        it "sets priority" do
          job = BatchJob.new(lower_priority_count: 1)
          assert_nil job.record_count
          job.perform_now
          assert_equal 3, job.record_count
          assert_equal BatchJob.priority + 3, job.priority
        end
      end
    end
  end
end

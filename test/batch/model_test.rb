require_relative "../test_helper"
module Batch
  class ModelTest < Minitest::Test
    class SimpleJob < RocketJob::Job
      include RocketJob::Batch

      self.destroy_on_complete = false

      input_category slice_size: 10
      output_category

      def perform(record)
        record
      end
    end

    describe RocketJob::Batch::Model do
      before do
        SimpleJob.delete_all
        @blah_exception =
          begin
            RocketJob.blah
          rescue StandardError => e
            e
          end
      end

      after do
        SimpleJob.delete_all
        @job.destroy if @job && !@job.new_record?
      end

      describe "#exception" do
        it "saves" do
          @job           = SimpleJob.new
          @job.exception = RocketJob::JobException.from_exception(@blah_exception)
          assert_equal true, @job.save!
        end

        it "fails" do
          @job = SimpleJob.new
          assert_equal true, @job.fail!(@blah_exception)
        end
      end

      describe "#percent_complete" do
        it "is 0 when the record count has not been set" do
          @job = SimpleJob.new
          assert_equal 0, @job.percent_complete
        end

        it "is 100 when completed" do
          @job = SimpleJob.new(state: :completed)
          assert @job.completed?
          assert_equal 100, @job.percent_complete
        end

        it "estimates progress from the remaining input slices" do
          @job = SimpleJob.new
          @job.upload { |records| (1..25).each { |i| records << i } }
          @job.record_count = 100
          # 3 slices * slice_size 10 = 30 input records still to process out of 100.
          assert_equal 70, @job.percent_complete
        end

        it "is 0 when more input records remain than the record count" do
          @job = SimpleJob.new
          @job.upload { |records| (1..25).each { |i| records << i } }
          @job.record_count = 5
          assert_equal 0, @job.percent_complete
        end
      end

      describe "#worker_names" do
        it "is empty when the job is not running" do
          @job = SimpleJob.new
          assert_empty @job.worker_names
        end

        it "returns the job worker when in the before sub-state" do
          @job = SimpleJob.create!(worker_name: "worker-1")
          @job.start!
          @job.sub_state = :before
          assert_equal ["worker-1"], @job.worker_names
        end

        it "returns the slice workers when processing" do
          @job = SimpleJob.create!
          @job.upload { |records| (1..25).each { |i| records << i } }
          @job.start!
          @job.input.next_slice("slice-worker")
          @job.sub_state = :processing
          assert_equal ["slice-worker"], @job.worker_names
        end
      end

      describe "#worker_count" do
        it "is 0 when the job is not running" do
          @job = SimpleJob.new
          assert_equal 0, @job.worker_count
        end

        it "is 1 in the before sub-state" do
          @job = SimpleJob.create!
          @job.start!
          @job.sub_state = :before
          assert_equal 1, @job.worker_count
        end

        it "caches the count for one second" do
          @job = SimpleJob.create!
          @job.start!
          @job.sub_state = :before
          assert_equal 1, @job.worker_count
          # Switching sub-state should not change the cached value within the same second.
          @job.sub_state = :processing
          assert_equal 1, @job.worker_count
        end
      end

      describe "#status" do
        it "reports queued slice counts when queued" do
          @job = SimpleJob.create!
          @job.upload { |records| (1..25).each { |i| records << i } }
          status = @job.status
          assert_equal 3, status["queued_slices"]
        end

        it "reports active, failed, and queued slices when running" do
          @job = SimpleJob.create!
          @job.upload { |records| (1..25).each { |i| records << i } }
          @job.start!
          @job.sub_state = :processing
          status = @job.status
          assert status.key?("active_slices")
          assert status.key?("failed_slices")
          assert status.key?("queued_slices")
        end
      end

      describe "#upload_file_name" do
        it "delegates to the input category file name" do
          @job = SimpleJob.new
          assert_nil @job.upload_file_name
          @job.upload_file_name = "data.csv"
          # Category#file_name wraps the value in an IOStreams path.
          assert_equal "data.csv", @job.upload_file_name.to_s
          assert_equal @job.input_category.file_name, @job.upload_file_name
        end
      end
    end
  end
end

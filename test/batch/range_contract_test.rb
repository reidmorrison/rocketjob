require_relative "../test_helper"

module Batch
  class RangeContractTest < Minitest::Test
    class RangeJob < RocketJob::Job
      include RocketJob::Batch

      self.destroy_on_complete = false

      input_category slice_size: 10
      input_contract RocketJob::Batch::RangeContract

      output_category

      def perform(range)
        [range.class.name, range.first_id, range.last_id, range.to_range.size]
      end
    end

    describe RocketJob::Batch::RangeContract do
      let(:job) { RangeJob.new }

      after do
        job.cleanup!
      end

      def output_records
        job.save!
        job.perform_now

        assert_predicate job, :completed?, -> { job.input.failed.first&.exception&.message }
        job.output.flat_map(&:to_a)
      end

      # Returns each range that #perform received, without the name of its class.
      def ranges
        output_records.map { |record| record.drop(1) }
      end

      it "gives #perform each range of an ascending range as a record of the contract" do
        assert_equal 25, job.upload(1..25)

        assert_equal [["RocketJob::Batch::RangeContract", 1, 10, 10],
                      ["RocketJob::Batch::RangeContract", 11, 20, 10],
                      ["RocketJob::Batch::RangeContract", 21, 25, 5]], output_records
      end

      it "gives #perform the highest ids first for a descending range, each range starting with its lowest id" do
        assert_equal 25, job.upload(25..1)

        assert_equal [[16, 25, 10], [6, 15, 10], [1, 5, 5]], ranges
      end

      it "reads Arrays of two ids by position, as Rocket Job 7 saved each range" do
        job.upload_slice([[1, 5], [6, 9]])

        assert_equal [[1, 5, 5], [6, 9, 4]], ranges
      end

      it "requires both ids" do
        job.upload_slice([[1, nil]])
        job.save!

        assert_raises(IOStreams::Errors::InvalidValue) { job.perform_now }
      end

      it "returns the range of its ids" do
        assert_equal 3..7, RocketJob::Batch::RangeContract.new(first_id: 3, last_id: 7).to_range
      end
    end
  end
end

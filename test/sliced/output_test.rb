require_relative "../test_helper"

module Sliced
  class OutputTest < Minitest::Test
    class OutputJob < RocketJob::Job
      include RocketJob::Batch

      input_category slice_size: 2
      output_category nils: true

      def perform(record)
        record
      end
    end

    describe RocketJob::Sliced::Output do
      let(:job) { OutputJob.new }
      let(:rows) { %w[hello world last slice] }

      let(:loaded_job) do
        job.output << rows[0, 2]
        job.output << rows[2, 2]
        job
      end

      after do
        job.cleanup!
      end

      describe "#download" do
        describe "block" do
          it "downloads" do
            lines = []
            loaded_job.download { |line| lines << line }
            assert_equal rows, lines
          end
        end
      end
    end
  end
end

require_relative "../test_helper"

module Batch
  class SlicedTest < Minitest::Test
    class CompressedJob < RocketJob::Job
      include RocketJob::Batch

      input_category slice_size: 2, serializer: :compress

      def perform(record)
        record
      end
    end

    class EncryptedJob < RocketJob::Job
      include RocketJob::Batch

      input_category slice_size: 2, serializer: :encrypt

      def perform(record)
        record
      end
    end

    describe RocketJob::Sliced do
      let(:text_file) { IOStreams.path(File.dirname(__FILE__), "files", "text.txt") }

      let(:job) { CompressedJob.new }

      after do
        job.cleanup!
      end

      describe "#upload" do
        describe "compressed" do
          it "readable" do
            job.upload(text_file.to_s)
            result = job.input.collect(&:to_a).join("\n") + "\n"
            assert_equal text_file.read, result
          end

          it "is compressed" do
            job.upload(text_file.to_s)
            assert_equal RocketJob::Sliced::CompressedSlice, job.input.first.class
          end
        end

        describe "encrypted" do
          let(:job) { EncryptedJob.new }

          it "readable" do
            job.upload(text_file.to_s)
            result = job.input.collect(&:to_a).join("\n") + "\n"
            assert_equal text_file.read, result
          end

          it "is encrypted" do
            job.upload(text_file.to_s)
            assert_equal RocketJob::Sliced::EncryptedSlice, job.input.first.class
          end
        end
      end
    end
  end
end

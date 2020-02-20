require_relative '../test_helper'

module Batch
  class SlicedTest < Minitest::Test
    describe RocketJob::Sliced do
      let(:text_file) { IOStreams.path(File.dirname(__FILE__), 'files', 'text.txt') }

      class CompressedJob < RocketJob::Job
        include RocketJob::Batch

        self.compress = true

        def perform(record)
          record
        end
      end

      class EncryptedJob < RocketJob::Job
        include RocketJob::Batch

        self.encrypt = true

        def perform(record)
          record
        end
      end

      class CompressedAndEncryptedJob < RocketJob::Job
        include RocketJob::Batch

        self.compress = true
        self.encrypt  = true

        def perform(record)
          record
        end
      end

      let(:job) { CompressedJob.new(slice_size: 2) }

      after do
        job.cleanup!
      end

      describe '#upload' do
        describe 'compressed' do
          it 'readable' do
            job.upload(text_file.to_s)
            result = job.input.collect(&:to_a).join("\n") + "\n"
            assert_equal text_file.read, result
          end

          it 'is compressed' do
            job.upload(text_file.to_s)
            assert_equal RocketJob::Sliced::CompressedSlice, job.input.first.class
          end
        end

        describe 'encrypted' do
          let(:job) { EncryptedJob.new(slice_size: 2) }

          it 'readable' do
            job.upload(text_file.to_s)
            result = job.input.collect(&:to_a).join("\n") + "\n"
            assert_equal text_file.read, result
          end

          it 'is encrypted' do
            job.upload(text_file.to_s)
            assert_equal RocketJob::Sliced::EncryptedSlice, job.input.first.class
          end
        end

        describe 'compressed and encrypted' do
          let(:job) { CompressedAndEncryptedJob.new(slice_size: 2) }

          it 'readable' do
            job.upload(text_file.to_s)
            result = job.input.collect(&:to_a).join("\n") + "\n"
            assert_equal text_file.read, result
          end

          it 'is compressed' do
            job.upload(text_file.to_s)
            assert_equal RocketJob::Sliced::EncryptedSlice, job.input.first.class
          end
        end

      end
    end
  end
end

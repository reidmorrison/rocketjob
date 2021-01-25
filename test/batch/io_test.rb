require_relative "../test_helper"

module Batch
  class IOTest < Minitest::Test
    class IOJob < RocketJob::Job
      include RocketJob::Batch

      def perform(record)
        record
      end
    end

    describe RocketJob::Batch::IO do
      let(:text_file) { IOStreams.path(File.dirname(__FILE__), "files", "text.txt") }
      let(:gzip_file) { IOStreams.path(File.dirname(__FILE__), "files", "text.txt.gz") }

      let(:job) { IOJob.new(slice_size: 2) }
      let(:rows) { %w[hello world last slice] }
      let(:delimited_rows) { rows.join("\n") + "\n" }

      let(:loaded_job) do
        job.output << rows[0, 2]
        job.output << rows[2, 2]
        job
      end

      after do
        job.cleanup!
      end

      describe "#download" do
        describe "file" do
          it "text" do
            IOStreams.temp_file("test", ".txt") do |file_name|
              loaded_job.download(file_name.to_s)
              result = ::File.open(file_name.to_s, &:read)
              assert_equal delimited_rows, result
            end
          end

          it "gzip" do
            IOStreams.temp_file("gzip_test", ".gz") do |file_name|
              loaded_job.download(file_name.to_s)
              result = Zlib::GzipReader.open(file_name.to_s, &:read)
              assert_equal delimited_rows, result
            end
          end
        end

        describe "stream" do
          let(:io_stream) { StringIO.new }

          it "text" do
            stream = IOStreams.stream(io_stream).file_name(text_file.to_s)
            loaded_job.download(stream)
            result = io_stream.string
            assert_equal delimited_rows, result
          end

          it "gzip" do
            stream = IOStreams.stream(io_stream).file_name(gzip_file.to_s)
            loaded_job.download(stream)
            io     = StringIO.new(io_stream.string)
            gz     = Zlib::GzipReader.new(io)
            result = gz.read
            gz.close
            assert_equal delimited_rows, result
          end
        end
      end

      describe "#upload" do
        describe "file" do
          it "text" do
            job.upload(text_file.to_s)
            result = job.input.collect(&:to_a).join("\n") + "\n"
            assert_equal text_file.read, result
          end

          it "gzip" do
            job.upload(gzip_file.to_s)
            result = job.input.collect(&:to_a).join("\n") + "\n"
            assert_equal gzip_file.read, result
          end
        end
      end
    end
  end
end

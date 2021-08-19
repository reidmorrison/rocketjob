require_relative "../test_helper"
require "csv"

module Batch
  class IOTest < Minitest::Test
    class IOJob < RocketJob::Job
      include RocketJob::Batch

      input_category slice_size: 2
      output_category nils: true

      def perform(record)
        record
      end
    end

    describe RocketJob::Batch::IO do
      let(:text_file) { IOStreams.path(File.dirname(__FILE__), "files", "text.txt") }
      let(:gzip_file) { IOStreams.path(File.dirname(__FILE__), "files", "text.txt.gz") }
      let(:csv_file) { IOStreams.path(File.dirname(__FILE__), "files", "test.csv") }

      let(:job) { IOJob.new }
      let(:rows) { %w[hello world last slice] }
      let(:delimited_rows) { rows.join("\n") + "\n" }

      let :csv_columns do
        header_line = csv_file.read.lines.first
        CSV.parse(header_line).first
      end

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
              assert_equal 4, loaded_job.download(file_name.to_s)
              result = ::File.open(file_name.to_s, &:read)
              assert_equal delimited_rows, result
            end
          end

          it "gzip" do
            IOStreams.temp_file("gzip_test", ".gz") do |file_name|
              assert_equal 4, loaded_job.download(file_name.to_s)
              result = Zlib::GzipReader.open(file_name.to_s, &:read)
              assert_equal delimited_rows, result
            end
          end

          it "parsed csv" do
            IOStreams.temp_file("csv_test", ".csv") do |file_name|
              job.input_category.format     = :auto
              job.output_category.format    = :auto
              job.output_category.columns   = csv_columns
              job.output_category.file_name = file_name
              assert_equal 3, job.upload(csv_file)
              job.perform_now
              assert_equal 3, job.download
              assert_equal csv_file.read, file_name.read
            end
          end

          it "bz2" do
            IOStreams.temp_file("bz2_test", ".bz2") do |file_name|
              job.output_category.serializer = :bz2
              # TODO: Binary formats should return the record count, instead of the slice count.
              assert_equal 2, loaded_job.download(file_name.to_s)
              result =
                File.open(file_name.to_s, "rb") do |input_stream|
                  io = ::Bzip2::FFI::Reader.new(input_stream)
                  io.read
                ensure
                  io.close
                end
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
            assert_equal 4, job.upload(text_file)
            result = job.input.collect(&:to_a).join("\n") + "\n"
            assert_equal text_file.read, result
          end

          it "gzip" do
            assert_equal 4, job.upload(gzip_file)
            result = job.input.collect(&:to_a).join("\n") + "\n"
            assert_equal gzip_file.read, result
          end

          it "raw csv" do
            assert_equal 4, job.upload(csv_file)
            result = job.input.collect(&:to_a).join("\n") + "\n"
            assert_equal csv_file.read, result
          end

          it "parsed csv" do
            job.input_category.format = :csv
            assert_equal 3, job.upload(csv_file)

            assert_equal csv_columns, job.input_category.columns

            result = job.input.collect(&:to_a).join("\n") + "\n"
            assert_equal csv_file.read, csv_columns.to_csv + result
          end

          it "autodetect csv" do
            job.input_category.format = :auto
            assert_equal 3, job.upload(csv_file)

            assert_equal csv_columns, job.input_category.columns

            result = job.input.collect(&:to_a).join("\n") + "\n"
            assert_equal csv_file.read, csv_columns.to_csv + result
          end
        end
      end
    end
  end
end

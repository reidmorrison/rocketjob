require_relative '../test_helper'

module Sliced
  class OutputTest < Minitest::Test
    describe RocketJob::Sliced::Output do
      before do
        @output = RocketJob::Sliced::Output.new(
          collection_name: 'rocket_job.slices.test',
          slice_size:      2
        )
        @output.delete_all
        @rows           = %w[hello world last slice]
        @delimited_rows = @rows.join("\n") + "\n"
        @output << @rows[0, 2]
        @output << @rows[2, 2]
      end

      after do
        @output.drop
      end

      describe '#download' do
        describe 'file' do
          before do
            @temp_file        = Tempfile.new('rocket_job')
            @output_file_name = @temp_file.to_path
          end

          after do
            @temp_file&.delete
          end

          it 'text supplying streams' do
            file_name = File.join(File.dirname(__FILE__), 'files', 'text.txt')
            streams   = IOStreams.streams_for_file_name(file_name)
            @output.download(@output_file_name, streams: streams)
            result = File.read(@output_file_name)
            assert_equal @delimited_rows, result
          end

          it 'text' do
            file_name        = File.join(File.dirname(__FILE__), 'files', 'text.txt')
            output_file_name = File.join(File.dirname(__FILE__), 'files', 'output_text.txt')
            @output.download(output_file_name)
            result = File.read(output_file_name)
            assert_equal @delimited_rows, result
            File.delete(output_file_name)
          end

          it 'gzip supplying streams' do
            file_name = File.join(File.dirname(__FILE__), 'files', 'text.txt.gz')
            streams   = IOStreams.streams_for_file_name(file_name)
            @output.download(@output_file_name, streams: streams)
            result = Zlib::GzipReader.open(@output_file_name, &:read)
            assert_equal @delimited_rows, result
          end

          it 'gzip' do
            file_name        = File.join(File.dirname(__FILE__), 'files', 'text.txt.gz')
            output_file_name = File.join(File.dirname(__FILE__), 'files', 'output_text.txt.gz')
            @output.download(output_file_name)
            result = Zlib::GzipReader.open(output_file_name, &:read)
            assert_equal @delimited_rows, result
            File.delete(output_file_name)
          end
        end

        describe 'stream' do
          before do
            @stream = StringIO.new
          end

          it 'text' do
            file_name = File.join(File.dirname(__FILE__), 'files', 'text.txt')
            streams   = IOStreams.streams_for_file_name(file_name)
            @output.download(@stream, streams: streams)
            result = @stream.string
            assert_equal @delimited_rows, result
          end

          it 'gzip' do
            file_name = File.join(File.dirname(__FILE__), 'files', 'text.txt.gz')
            streams   = IOStreams.streams_for_file_name(file_name)
            @output.download(@stream, streams: streams)
            io     = StringIO.new(@stream.string)
            gz     = Zlib::GzipReader.new(io)
            result = gz.read
            gz.close
            assert_equal @delimited_rows, result
          end
        end
      end
    end
  end
end

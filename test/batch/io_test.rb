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

      def read_bz2(file_name)
        File.open(file_name.to_s, "rb") do |input_stream|
          io = ::Bzip2::FFI::Reader.new(input_stream)
          io.read
        ensure
          io.close
        end
      end

      describe "#download" do
        describe "file" do
          it "text" do
            IOStreams.temp_file("test", ".txt") do |file_name|
              assert_equal 4, loaded_job.download(file_name.to_s)
              result = ::File.read(file_name.to_s)

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
              job.output_category.schema    = {"fields" => csv_columns.collect { |column| {"name" => column} }}
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

          it "encrypted_bz2" do
            IOStreams.temp_file("encrypted_bz2_test", ".bz2") do |file_name|
              job.output_category.serializer = :encrypted_bz2
              loaded_job.download(file_name.to_s)

              assert_equal delimited_rows, read_bz2(file_name)
            end
          end

          %i[bz2 encrypted_bz2].each do |serializer|
            it "#{serializer} with a header line" do
              IOStreams.temp_file("#{serializer}_header_test", ".bz2") do |file_name|
                job.output_category.serializer = serializer
                loaded_job.download(file_name.to_s, header_line: "header")

                assert_equal "header\n#{delimited_rows}", read_bz2(file_name)
              end
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

          it "raises for the options that read the lines of a file, which v8 removed, before anything is uploaded" do
            error = assert_raises(ArgumentError) { job.upload(text_file, delimiter: "\n", embedded_within: '"') }

            assert_equal "delimiter:, embedded_within: were removed in Rocket Job v8, which reads the lines of a file " \
                         "itself: line endings are detected, and the input category's format reads a quoted value " \
                         "with line breaks, see https://rocketjob.reidmorrison.com/upgrading.html#line-options-of-upload",
                         error.message
            assert_match(/\Abuffer_size: was removed/, assert_raises(ArgumentError) { job.upload(text_file, buffer_size: 1) }.message)
            assert_equal 0, job.input.count
          end

          it "raises for an option that it does not take" do
            error = assert_raises(ArgumentError) { job.upload(text_file, encoding: "UTF-8") }

            assert_equal "Unknown keyword argument :encoding when uploading a file", error.message
          end

          it "keeps the line of each line of a file without a format" do
            job.input_category.slice_size = 10
            job.upload(csv_file)
            slice = job.input.first

            assert_equal :lines, slice.records.format
            assert_equal [1, 2, 3, 4], Array.new(4) { |index| slice.line_number_at(index) }
            assert_equal [1, 2, 3, 4], Array.new(4) { |index| slice.record_number_at(index) }
          end

          it "raw csv" do
            assert_equal 4, job.upload(csv_file)
            result = job.input.collect(&:to_a).join("\n") + "\n"

            assert_equal csv_file.read, result
          end

          it "parsed csv" do
            job.input_category.format = :csv

            assert_equal 3, job.upload(csv_file)

            assert_nil job.input_category.columns
            assert_equal csv_columns, job.input.first.records.header

            result = job.input.collect(&:to_a).join("\n") + "\n"

            assert_equal csv_file.read, csv_columns.to_csv + result
          end

          it "autodetect csv" do
            job.input_category.format = :auto

            assert_equal 3, job.upload(csv_file)

            assert_equal :csv, job.input_category.format
            assert_equal csv_columns, job.input.first.records.header

            result = job.input.collect(&:to_a).join("\n") + "\n"

            assert_equal csv_file.read, csv_columns.to_csv + result
          end
        end

        describe "block without a format" do
          it "keeps each record as it is written, one per record, as Rocket Job 7 did" do
            job.input_category.slice_size = 10
            records                       = ["two\nlines", 42, [1, 99], {"a" => 1}, nil]

            assert_equal(5, job.upload { |io| records.each { |record| io << record } })
            slice = job.input.first

            assert_equal records, slice.to_a
            assert_instance_of Array, slice.records
            assert_equal [1, 2, 3, 4, 5], Array.new(5) { |index| slice.record_number_at(index) }
          end
        end

        describe "file without a format" do
          it "is stored as the lines of a slice, which a worker of Rocket Job 7 fails rather than processing none" do
            job.upload(text_file)
            stored   = job.input.collection.find.first["records"]
            document = Hash.from_bson(BSON::ByteBuffer.new(Zlib::Inflate.inflate(stored.data)))

            assert_equal RocketJob::Sliced::Slice::ROWS_GUARD, document["r"]
            assert_equal "lines", document["s"]["format"]
          end
        end

        describe "Range" do
          before do
            job.input_category.slice_size = 10
          end

          it "handle single value" do
            count = job.upload(1..1)

            assert_equal 1, count, job.input.first.inspect
            assert_equal [[[1, 1]]], job.input.collect(&:to_a)
          end

          it "handle single range" do
            count = job.upload(1..10)

            assert_equal 10, count, job.input.first.inspect
            assert_equal 10, job.record_count
            assert_equal [[[1, 10]]], job.input.collect(&:to_a)
          end

          it "handle longer range" do
            count = job.upload(1..11)

            assert_equal 11, count, job.input.collect(&:to_a).inspect
            assert_equal [[[1, 10]], [[11, 11]]], job.input.collect(&:to_a)
          end

          it "handle even longer range" do
            count = job.upload(0..44)

            assert_equal 45, count, job.input.collect(&:to_a).inspect
            assert_equal [[[0, 9]], [[10, 19]], [[20, 29]], [[30, 39]], [[40, 44]]], job.input.collect(&:to_a)
          end

          it "reports the percent complete as its ranges are processed" do
            job.upload(1..40)
            job.start
            job.sub_state = :processing

            assert_equal 0, job.percent_complete
            job.input.first.destroy

            assert_equal 25, job.percent_complete
          end
        end

        describe "Range in reverse" do
          before do
            job.input_category.slice_size = 10
          end

          it "handle single value" do
            count = job.upload(1..1)

            assert_equal 1, count, job.input.first.inspect
            assert_equal [[[1, 1]]], job.input.collect(&:to_a)
            assert_equal [1], job.input.collect(&:first_record_number)
          end

          it "handle single range" do
            count = job.upload(10..1)

            assert_equal 10, count, job.input.first.inspect
            assert_equal [[[1, 10]]], job.input.collect(&:to_a)
            assert_equal [1], job.input.collect(&:first_record_number)
          end

          it "handle longer range" do
            count = job.upload(11..1)

            assert_equal 11, count, job.input.collect(&:to_a).inspect
            assert_equal [[[2, 11]], [[1, 1]]], job.input.collect(&:to_a)
            assert_equal [1, 2], job.input.collect(&:first_record_number)
          end

          it "handle even longer range" do
            count = job.upload(44..0)

            assert_equal 45, count, job.input.collect(&:to_a).inspect
            assert_equal [[[35, 44]], [[25, 34]], [[15, 24]], [[5, 14]], [[0, 4]]], job.input.collect(&:to_a)
            assert_equal [1, 2, 3, 4, 5], job.input.collect(&:first_record_number)
          end

          it "handle partial range" do
            count = job.upload(44..5)

            assert_equal 40, count, job.input.collect(&:to_a).inspect
            assert_equal [[[35, 44]], [[25, 34]], [[15, 24]], [[5, 14]]], job.input.collect(&:to_a)
            assert_equal [1, 2, 3, 4], job.input.collect(&:first_record_number)
          end

          it "uploads each negative id once" do
            count = job.upload(-1..-25)

            assert_equal 25, count
            assert_equal [[[-10, -1]], [[-20, -11]], [[-25, -21]]], job.input.collect(&:to_a)
          end

          it "does not upload the end that the range excludes" do
            count = job.upload(20...1)

            assert_equal 19, count
            assert_equal [[[11, 20]], [[2, 10]]], job.input.collect(&:to_a)
          end
        end

        describe "Range that excludes its end" do
          before do
            job.input_category.slice_size = 10
          end

          it "does not upload its end" do
            count = job.upload(1...21)

            assert_equal 20, count
            assert_equal 20, job.record_count
            assert_equal [[[1, 10]], [[11, 20]]], job.input.collect(&:to_a)
          end

          it "uploads nothing when it is empty" do
            count = job.upload(5...5)

            assert_equal 0, count
            assert_equal 0, job.input.count
          end
        end
      end

      describe "#upload argument validation" do
        it "rejects supplying both an object and a block" do
          assert_raises(ArgumentError) { job.upload(text_file) { |io| io << "x" } }
        end

        it "rejects stream options when uploading a block" do
          assert_raises(ArgumentError) { job.upload(delimiter: ",") { |io| io << "x" } }
        end

        it "rejects validate_rows when uploading a Range or a query" do
          error = assert_raises(ArgumentError) { job.upload(1..10, validate_rows: true) }
          assert_equal "Unknown keyword arguments when uploading a Range. Only accepts :category, or :slice_batch_size",
                       error.message
        end

        it "accepts validate_rows: false when uploading a Range, which uploads values rather than rows" do
          assert_equal 10, job.upload(1..10, validate_rows: false)
        end

        it "rejects keyword arguments when uploading a Range" do
          assert_raises(ArgumentError) { job.upload(1..10, file_name: "x.txt") }
        end

        it "rejects a Range without an end" do
          error = assert_raises(ArgumentError) { job.upload(1..) }
          assert_includes error.message, "Integer at each end"
        end

        it "rejects a Range without a beginning" do
          assert_raises(ArgumentError) { job.upload(..10) }
        end

        it "rejects :columns when uploading a file" do
          assert_raises(ArgumentError) { job.upload(text_file, columns: [:a]) }
        end
      end

      describe "#upload_slice" do
        it "inserts the slice and updates the record count" do
          count = job.upload_slice(%w[a b c])

          assert_equal 3, count
          assert_equal 3, job.record_count
          assert_equal 1, job.input.count
          assert_equal %w[a b c], job.input.first.to_a
        end
      end

      describe "#download" do
        it "raises when the job is still processing" do
          job.start
          job.sub_state = :processing
          error = assert_raises(RuntimeError) { job.download("/tmp/out.txt") }
          assert_includes error.message, "Cannot download incomplete job"
        end
      end
    end
  end
end

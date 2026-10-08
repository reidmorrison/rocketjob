require_relative "../test_helper"

module Batch
  # Text must reach MongoDB as UTF-8, since BSON strings are UTF-8, and come back out byte for byte.
  # Binary files are only copied, never stored as records.
  class EncodingTest < Minitest::Test
    class EncodingJob < RocketJob::Job
      include RocketJob::Batch

      self.destroy_on_complete = false

      input_category slice_size: 2
      output_category

      def perform(record)
        record
      end
    end

    describe "Encoding" do
      let(:job) { EncodingJob.new }
      let(:utf8_lines) { ["José", "naïve café", "日本語", "emoji 🚀"] }
      let(:utf8_text) { utf8_lines.join("\n") + "\n" }

      after do
        job.cleanup!
      end

      def with_file(extension, data)
        IOStreams.temp_file("encoding_test", extension) do |path|
          ::File.binwrite(path.to_s, data)
          yield(IOStreams.path(path.to_s))
        end
      end

      def input_records
        job.input.collect(&:to_a).flatten
      end

      def process(job)
        job.save!
        job.perform_now
      end

      describe "#upload" do
        it "keeps UTF-8 text decoded with the encode stream" do
          with_file(".txt", utf8_text) do |path|
            assert_equal 4, job.upload(path.option(:encode, encoding: "UTF-8"))
          end

          assert_equal utf8_lines, input_records
          assert(input_records.all? { |record| record.encoding == Encoding::UTF_8 })
        end

        it "keeps UTF-8 text in a compressed file" do
          IOStreams.temp_file("encoding_test", ".txt.gz") do |path|
            IOStreams.path(path.to_s).write(utf8_text)

            assert_equal 4, job.upload(IOStreams.path(path.to_s).option(:encode, encoding: "UTF-8"))
          end

          assert_equal utf8_lines, input_records
        end

        it "reads UTF-8 text by default" do
          with_file(".txt", utf8_text) do |path|
            assert_equal 4, job.upload(path)
          end

          assert_equal utf8_lines, input_records
          assert(input_records.all? { |record| record.encoding == Encoding::UTF_8 })
        end

        it "removes a UTF-8 byte order mark" do
          with_file(".txt", "\xEF\xBB\xBF".b + utf8_text.b) do |path|
            assert_equal 4, job.upload(path)
          end

          assert_equal utf8_lines, input_records
        end

        it "converts text in the encoding set on the path to UTF-8" do
          with_file(".txt", "Jos\xE9\nZ\xFCrich\n".b) do |path|
            assert_equal 2, job.upload(path.option(:encode, encoding: "Windows-1252"))
          end

          assert_equal %w[José Zürich], input_records
        end

        it "keeps UTF-8 records written with a block" do
          job.upload { |records| utf8_lines.each { |line| records << line } }

          assert_equal utf8_lines, input_records
        end

        it "rejects text that is not UTF-8, and leaves no partial upload" do
          with_file(".txt", "first\nJos\xE9\n".b) do |path|
            assert_raises(Encoding::UndefinedConversionError) { job.upload(path) }
          end

          assert_equal 0, job.input.count
        end

        it "rejects a binary file, and leaves no partial upload" do
          with_file(".bin", (0..255).to_a.pack("C*")) do |path|
            assert_raises(Encoding::UndefinedConversionError) { job.upload(path) }
          end

          assert_equal 0, job.input.count
        end

        describe "csv" do
          before do
            job.input_category.format = :csv
          end

          it "removes non-printable characters" do
            with_file(".csv", "name,city\nJack\u0007,Paris\u0000\n") do |path|
              assert_equal 1, job.upload(path)
            end

            assert_equal %w[name city], job.input_category.columns
            assert_equal ["Jack,Paris"], input_records
          end

          it "keeps UTF-8 characters" do
            with_file(".csv", "name,city\nJosé,Zürich\n日本,東京\n") do |path|
              assert_equal 2, job.upload(path)
            end

            assert_equal ["José,Zürich", "日本,東京"], input_records
          end

          it "removes a UTF-8 byte order mark before a quoted header" do
            with_file(".csv", "\xEF\xBB\xBF".b + "\"name\",\"city\"\n\"José\",\"Zürich\"\n".b) do |path|
              assert_equal 1, job.upload(path)
            end

            assert_equal %w[name city], job.input_category.columns
            assert_equal ["\"José\",\"Zürich\""], input_records
          end

          it "removes non-ASCII characters when the path is set to US-ASCII" do
            with_file(".csv", "name,city\nJosé,Zürich\n") do |path|
              assert_equal 1, job.upload(path.option(:encode, encoding: "US-ASCII"))
            end

            assert_equal ["Jos,Zrich"], input_records
          end

          it "converts text in the encoding set on the path to UTF-8" do
            with_file(".csv", "name,city\nJos\xE9,Z\xFCrich\n".b) do |path|
              assert_equal 1, job.upload(path.option(:encode, encoding: "Windows-1252"))
            end

            assert_equal ["José,Zürich"], input_records
          end

          it "removes characters that are not valid UTF-8" do
            with_file(".csv", "name,city\nJos\xE9,Z\xFCrich\n".b) do |path|
              assert_equal 1, job.upload(path)
            end

            assert_equal ["Jos,Zrich"], input_records
            assert(input_records.all?(&:valid_encoding?))
          end
        end
      end

      describe "processing" do
        %i[none compress encrypt].each do |serializer|
          it "keeps UTF-8 records stored with the #{serializer} serializer" do
            job.input_category.serializer  = serializer
            job.output_category.serializer = serializer
            job.upload { |records| utf8_lines.each { |line| records << line } }

            process(job)

            assert_predicate job, :completed?
            assert_equal utf8_lines, job.output.collect(&:to_a).flatten
          end
        end
      end

      describe "#download" do
        before do
          job.output << utf8_lines[0, 2]
          job.output << utf8_lines[2, 2]
        end

        it "writes UTF-8 text" do
          IOStreams.temp_file("encoding_test", ".txt") do |path|
            assert_equal 4, job.download(path.to_s)
            data = ::File.binread(path.to_s)

            assert_equal utf8_text.b, data
          end
        end

        it "writes UTF-8 text to a compressed file" do
          IOStreams.temp_file("encoding_test", ".txt.gz") do |path|
            assert_equal 4, job.download(path.to_s)
            data = Zlib::GzipReader.open(path.to_s, &:read)

            assert_equal utf8_text.b, data.b
          end
        end

        it "writes UTF-8 text to a bzip2 output slice" do
          job.output_category.serializer = :bz2
          job.output.delete_all
          job.output << utf8_lines

          IOStreams.temp_file("encoding_test", ".txt.bz2") do |path|
            job.download(path.to_s)

            assert_equal utf8_text.b, IOStreams.path(path.to_s).stream(:bz2).read.b
          end
        end

        it "writes UTF-8 text with a header line" do
          IOStreams.temp_file("encoding_test", ".txt") do |path|
            job.download(path.to_s, header_line: "Ünïcode header")

            assert_equal "Ünïcode header\n#{utf8_text}".b, ::File.binread(path.to_s)
          end
        end
      end

      describe RocketJob::Jobs::CopyFileJob do
        it "copies a binary file byte for byte" do
          data = (0..255).to_a.pack("C*") * 300

          with_file(".bin", data) do |source|
            IOStreams.temp_file("encoding_test", ".bin") do |target|
              RocketJob::Jobs::CopyFileJob.new(source_url: source.to_s, target_url: target.to_s).perform_now

              assert_equal data, ::File.binread(target.to_s)
            end
          end
        end

        it "copies a UTF-8 file with a byte order mark byte for byte" do
          data = "\xEF\xBB\xBF".b + utf8_text.b

          with_file(".csv", data) do |source|
            IOStreams.temp_file("encoding_test", ".csv") do |target|
              RocketJob::Jobs::CopyFileJob.new(source_url: source.to_s, target_url: target.to_s).perform_now

              assert_equal data, ::File.binread(target.to_s)
            end
          end
        end
      end
    end
  end
end

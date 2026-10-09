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
            assert_equal 4, job.upload(path.encoding("UTF-8"))
          end

          assert_equal utf8_lines, input_records
          assert(input_records.all? { |record| record.encoding == Encoding::UTF_8 })
        end

        it "keeps UTF-8 text in a compressed file" do
          IOStreams.temp_file("encoding_test", ".txt.gz") do |path|
            IOStreams.path(path.to_s).write(utf8_text)

            assert_equal 4, job.upload(IOStreams.path(path.to_s).encoding("UTF-8"))
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
            assert_equal 2, job.upload(path.encoding("Windows-1252:UTF-8"))
          end

          assert_equal %w[José Zürich], input_records
        end

        it "keeps UTF-8 records written with a block" do
          job.upload { |records| utf8_lines.each { |line| records << line } }

          assert_equal utf8_lines, input_records
        end

        %i[none compress encrypt].each do |serializer|
          it "names a record written with a block that is not valid UTF-8, and leaves no partial upload, with the #{serializer} serializer" do
            job.input_category.serializer = serializer
            records                       = ["first", "second", "third", "Jos\xE9", "fifth"]

            error = assert_raises(EncodingError) { job.upload { |io| records.each { |record| io << record } } }

            assert_includes error.message, "Cannot upload record 4,"
            assert_equal 0, job.input.count
          end
        end

        it "names a binary record within a hash" do
          error = assert_raises(EncodingError) do
            job.upload { |io| io << {"name" => "Jack"} << {"name" => "José".b} }
          end

          assert_includes error.message, "Cannot upload record 2,"
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
              assert_equal 1, job.upload(path.encoding("US-ASCII"))
            end

            assert_equal ["Jos,Zrich"], input_records
          end

          it "converts text in the encoding set on the path to UTF-8" do
            with_file(".csv", "name,city\nJos\xE9,Z\xFCrich\n".b) do |path|
              assert_equal 1, job.upload(path.encoding("Windows-1252:UTF-8"))
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

      describe "#download fixed width" do
        before do
          job.output_category.format         = :fixed
          job.output_category.format_options = {layout: [{size: 10, key: "name"}, {size: 5, key: "zip"}]}
          job.output << ["José      12345", "Jack      54321"]
        end

        it "rejects a character that is not ASCII" do
          IOStreams.temp_file("encoding_test", ".txt") do |path|
            assert_raises(Encoding::UndefinedConversionError) { job.download(path.to_s) }
          end
        end

        it "writes the encoding set on the path, one byte per character" do
          IOStreams.temp_file("encoding_test", ".txt") do |path|
            job.download(IOStreams.path(path.to_s).encoding("ISO-8859-1"))
            lines = ::File.binread(path.to_s).lines

            assert_equal ["Jos\xE9      12345\n".b, "Jack      54321\n".b], lines
            assert(lines.all? { |line| line.bytesize == 16 })
          end
        end
      end

      describe "#download with a bz2 serializer" do
        before do
          job.output_category.serializer = :bz2
        end

        # Returns the text of the downloaded bzip2 file, as bytes.
        def download_bz2
          IOStreams.temp_file("encoding_test", ".txt.bz2") do |path|
            job.download(path.to_s)
            IOStreams.path(path.to_s).stream(:bz2).read.b
          end
        end

        def fixed_width
          job.output_category.format         = :fixed
          job.output_category.format_options = {layout: [{size: 10, key: "name"}, {size: 5, key: "zip"}]}
        end

        it "rejects a fixed width character that is not ASCII when the slice is written" do
          fixed_width

          assert_raises(Encoding::UndefinedConversionError) { job.output << ["José      12345"] }
        end

        it "writes fixed width in the output category's encoding, one byte per character" do
          fixed_width
          job.output_category.encoding = "ISO-8859-1"
          job.output << ["José      12345", "Jack      54321"]

          assert_equal "Jos\xE9      12345\nJack      54321\n".b, download_bz2
        end

        it "writes the header line in the output category's encoding" do
          job.output_category.format   = :csv
          job.output_category.columns  = %w[name city]
          job.output_category.encoding = "ISO-8859-1"
          job.output << ["José,Zürich"]

          assert_equal "name,city\nJos\xE9,Z\xFCrich\n".b, download_bz2
        end

        it "writes the header line of output written by the encrypted_bz2 serializer" do
          job.output_category.serializer = :encrypted_bz2
          job.output_category.format     = :csv
          job.output_category.columns    = %w[name city]
          job.output << ["Jack,Paris"]

          assert_equal "name,city\nJack,Paris\n".b, download_bz2
        end

        it "rejects an encoding set on the download path, since the slices are written in the category's" do
          job.output << ["Jack"]

          IOStreams.temp_file("encoding_test", ".txt.bz2") do |path|
            error = assert_raises(ArgumentError) { job.download(IOStreams.path(path.to_s).encoding("ISO-8859-1")) }

            assert_includes error.message, "output category's `encoding`"
          end
        end
      end

      describe "the category's encoding" do
        it "converts an uploaded file from the input category's encoding" do
          job.input_category.encoding = "Windows-1252"

          with_file(".txt", "Jos\xE9\nZ\xFCrich\n".b) do |path|
            assert_equal 2, job.upload(path.to_s)
          end

          assert_equal %w[José Zürich], input_records
        end

        it "converts a tabular file from the input category's encoding, instead of removing its characters" do
          job.input_category.format   = :csv
          job.input_category.encoding = "Windows-1252"

          with_file(".csv", "name,city\nJos\xE9,Z\xFCrich\n".b) do |path|
            assert_equal 1, job.upload(path.to_s)
          end

          assert_equal ["José,Zürich"], input_records
        end

        it "uses the encoding set on the path instead" do
          job.input_category.encoding = "Windows-1252"

          with_file(".txt", "José\n") do |path|
            assert_equal 1, job.upload(path.encoding("UTF-8"))
          end

          assert_equal ["José"], input_records
        end

        it "is kept with the job, so that a worker that uploads the category's file uses it" do
          with_file(".txt", "Jos\xE9\n".b) do |path|
            job.input_category.file_name = path.to_s
            job.input_category.encoding  = "Windows-1252"
            job.save!
            loaded = EncodingJob.find(job.id)

            assert_equal 1, loaded.upload
            assert_equal ["José"], loaded.input.collect(&:to_a).flatten
          end
        end

        it "converts a downloaded file to the output category's encoding" do
          job.output_category.encoding = "ISO-8859-1"
          job.output << %w[José Zürich]

          IOStreams.temp_file("encoding_test", ".txt") do |path|
            job.download(path.to_s)

            assert_equal "Jos\xE9\nZ\xFCrich\n".b, ::File.binread(path.to_s)
          end
        end

        it "writes fixed width in the output category's encoding, one byte per character" do
          job.output_category.format         = :fixed
          job.output_category.format_options = {layout: [{size: 10, key: "name"}, {size: 5, key: "zip"}]}
          job.output_category.encoding       = "ISO-8859-1"
          job.output << ["José      12345"]

          IOStreams.temp_file("encoding_test", ".txt") do |path|
            job.download(path.to_s)

            assert_equal "Jos\xE9      12345\n".b, ::File.binread(path.to_s)
          end
        end

        it "must be one encoding that Ruby knows" do
          category = job.input_category

          category.encoding = "Windows-1252:UTF-8"

          refute_predicate category, :valid?
          assert_includes category.errors[:encoding].first, "not a conversion"

          category.encoding = "Latin-9999"

          refute_predicate category, :valid?

          category.encoding = "IBM037"

          assert_predicate category, :valid?
        end
      end

      describe "the input category's invalid_characters" do
        let(:windows_1252_csv) { "name,city\nJos\xE9,Z\xFCrich\n".b }

        before do
          job.input_category.format = :csv
        end

        def upload_csv(data, path_encoding: nil)
          with_file(".csv", data) do |path|
            path = path.encoding(**path_encoding) if path_encoding
            job.upload(path)
          end
        end

        it "removes them from a tabular file by default" do
          upload_csv(windows_1252_csv)

          assert_equal ["Jos,Zrich"], input_records
        end

        it "replaces them with U+FFFD" do
          job.input_category.invalid_characters = :replace
          upload_csv(windows_1252_csv)

          assert_equal ["Jos�,Z�rich"], input_records
        end

        it "raises, naming the line of the first one, and uploads nothing" do
          job.input_category.invalid_characters = :raise

          error = assert_raises(IOStreams::Errors::InvalidEncoding) { upload_csv(windows_1252_csv) }

          assert_equal 2, error.line_number
          assert_equal 0, job.input.count
        end

        it "raises for a line by default, and removes them when requested" do
          job.input_category.format = nil
          assert_raises(IOStreams::Errors::InvalidEncoding) { upload_csv("Jos\xE9\n".b) }

          job.input_category.invalid_characters = :remove
          upload_csv("Jos\xE9\n".b)

          assert_equal ["Jos"], input_records
        end

        it "uses the replace: set on the path instead" do
          job.input_category.invalid_characters = :raise
          upload_csv(windows_1252_csv, path_encoding: {replace: "?"})

          assert_equal ["Jos?,Z?rich"], input_records
        end

        it "must be :remove, :replace or :raise" do
          job.input_category.invalid_characters = :ignore

          refute_predicate job.input_category, :valid?
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

        # Returns the bytes of the target file, after copying the supplied data with the supplied job arguments.
        def copy(data, extension: ".csv", **args)
          with_file(".csv", data) do |source|
            IOStreams.temp_file("encoding_test", extension) do |target|
              RocketJob::Jobs::CopyFileJob.new(source_url: source.to_s, target_url: target.to_s, **args).perform_now
              # Decompressed by the streams in the target's name, such as .gz.
              IOStreams.path(target.to_s).encoding("BINARY").read
            end
          end
        end

        it "converts the text from the source encoding to UTF-8" do
          assert_equal "José,Zürich\n".b, copy("Jos\xE9,Z\xFCrich\n".b, source_encoding: "Windows-1252")
        end

        it "converts UTF-8 text to the target encoding" do
          assert_equal "Jos\xE9,Z\xFCrich\n".b, copy("José,Zürich\n", target_encoding: "ISO-8859-1")
        end

        it "converts the text through the target's streams" do
          data = copy("Jos\xE9\n".b, extension: ".csv.gz", source_encoding: "Windows-1252", target_streams: {gz: {}})

          assert_equal "José\n".b, data
        end

        it "must be one encoding that Ruby knows" do
          job = RocketJob::Jobs::CopyFileJob.new(source_url: "a.csv", target_url: "b.csv", target_encoding: "Latin-9999")

          refute_predicate job, :valid?
          assert_includes job.errors[:target_encoding].first, "Latin-9999"
        end
      end
    end
  end
end

require_relative "../test_helper"

module Batch
  # How tabular input is read during upload, and parsed by the workers.
  class TabularInputTest < Minitest::Test
    class TabularJob < RocketJob::Job
      include RocketJob::Batch

      self.destroy_on_complete = false

      input_category format: :csv
      output_category

      def perform(record)
        record
      end
    end

    describe "Tabular input" do
      let(:job) { TabularJob.new }

      after do
        job.cleanup!
      end

      def with_file(extension, data, &)
        IOStreams.temp_file("tabular_input_test", extension) do |path|
          ::File.write(path.to_s, data)
          yield(path.to_s)
        end
      end

      def upload(extension, data, **)
        with_file(extension, data) { |file_name| job.upload(file_name, **) }
      end

      def input_records
        job.input.collect(&:to_a).flatten(1)
      end

      def output_records
        job.save!
        job.perform_now
        job.output.collect(&:to_a).flatten(1)
      end

      describe "blank lines before the header row" do
        let(:csv) { "\n  \nName,Age\nJack,21\n" }

        it "skips them, and reads the header row after them" do
          assert_equal 1, upload(".csv", csv)

          assert_equal %w[name age], job.input_category.columns
          assert_equal ["Jack,21"], input_records
          assert_equal [{"name" => "Jack", "age" => "21"}], output_records
        end

        it "skips them when they are written to a block" do
          count =
            job.upload do |records|
              records << ""
              records << "Name,Age"
              records << "Jack,21"
            end

          assert_equal 1, count
          assert_equal %w[name age], job.input_category.columns
          assert_equal [{"name" => "Jack", "age" => "21"}], output_records
        end

        it "calls on_first with the header row" do
          header = nil
          upload(".csv", csv, on_first: ->(row) { header = row })

          assert_equal "Name,Age", header
        end
      end

      describe "format :auto" do
        before do
          job.input_category.format = :auto
        end

        it "uploads the first record of a JSON file, which has no header row" do
          assert_equal 2, upload(".json", %({"name":"Jack"}\n{"name":"Jill"}\n))

          assert_equal :json, job.input_category.format
          assert_equal [{"name" => "Jack"}, {"name" => "Jill"}], output_records
        end

        it "reads the header row of a CSV file" do
          assert_equal 1, upload(".csv", "Name\nJack\n")

          assert_equal :csv, job.input_category.format
          assert_equal [{"name" => "Jack"}], output_records
        end
      end

      describe "schema" do
        let(:schema) do
          {
            "fields" => [
              {"name" => "name"},
              {"name" => "age", "type" => "integer"},
              {"name" => "joined", "type" => "date"}
            ]
          }
        end

        let(:csv) { "Name,Age,Joined\nJack,21,2026-10-20\nJill,22,2026-10-21\n" }

        let(:records) do
          [
            {"name" => "Jack", "age" => 21, "joined" => Date.new(2026, 10, 20)},
            {"name" => "Jill", "age" => 22, "joined" => Date.new(2026, 10, 21)}
          ]
        end

        before do
          job.input_category.schema = schema
        end

        it "uploads the lines, and keeps the header row as it is in the file" do
          assert_equal 2, upload(".csv", csv)

          assert_equal %w[Name Age Joined], job.input_category.columns
          assert_equal ["Jack,21,2026-10-20", "Jill,22,2026-10-21"], input_records
        end

        it "parses each line by the schema on the workers, keyed by the names of its fields" do
          upload(".csv", csv)

          assert_equal records, output_records
        end

        it "reads the header row of each file uploaded, rather than the columns copied from an earlier run" do
          job.input_category.columns = %w[Joined Name Age]

          upload(".csv", csv)

          assert_equal %w[Name Age Joined], job.input_category.columns
          assert_equal records, output_records
        end

        it "matches the columns of the header row to the fields whatever their case, spaces and punctuation" do
          job.input_category.schema = {"fields" => [{"name" => "first_name"}, {"name" => "e_mail"}]}

          upload(".csv", "First Name,E-Mail\nJack,jack@example.org\n")

          assert_equal [{"first_name" => "Jack", "e_mail" => "jack@example.org"}], output_records
        end

        it "raises when the header row does not match the fields, and uploads nothing" do
          assert_raises(IOStreams::Errors::InvalidHeader) { upload(".csv", "Name,Height\nJack,180\n") }
          assert_equal 0, job.input.count
        end

        it "reads the text as UTF-8, keeping letters that are not ASCII" do
          upload(".csv", "Name,Age,Joined\nJosé,21,2026-10-20\n")

          assert_equal ["José,21,2026-10-20"], input_records
          assert_equal "José", output_records.first["name"]
        end

        it "raises for text that is not valid UTF-8, and uploads nothing" do
          assert_raises(IOStreams::Errors::InvalidEncoding) { upload(".csv", "Name,Age,Joined\nJos\xE9,21,2026-10-20\n".b) }
          assert_equal 0, job.input.count
        end

        it "skips blank lines before the header row" do
          assert_equal 2, upload(".csv", "\n\n#{csv}")

          assert_equal records, output_records
        end

        it "skips rows of only blank values before the header row, such as the empty top row of a spreadsheet" do
          header = nil
          count  = upload(".csv", %(,,\n" ","",\n#{csv}), stream_mode: :hash, on_first: ->(row) { header = row })

          assert_equal 2, count
          assert_equal "Name,Age,Joined", header
          assert_equal %w[Name Age Joined], job.input_category.columns
          assert_equal records, output_records
        end

        it "reads a file without a header row by the order of the fields" do
          job.input_category.schema = schema.merge("header" => false)

          assert_equal 2, upload(".csv", "Jack,21,2026-10-20\nJill,22,2026-10-21\n")

          assert_nil job.input_category.columns
          assert_equal records, output_records
        end

        it "reads JSON by the schema, uploading its first record" do
          job.input_category.format = :json

          assert_equal 2, upload(".json", %({"name":"Jack","age":21,"joined":"2026-10-20"}\n{"name":"Jill","age":22,"joined":"2026-10-21"}\n))

          assert_equal records, output_records
        end

        it "reads fixed width by the width of each field" do
          job.input_category.format = :fixed
          job.input_category.schema = {
            "fields" => [
              {"name" => "name", "width" => 4},
              {"name" => "age", "type" => "integer", "width" => 2},
              {"name" => "joined", "type" => "date", "width" => 10}
            ]
          }

          assert_equal 2, upload(".txt", "Jack212026-10-20\nJill222026-10-21\n")

          assert_equal records, output_records
        end

        it "reads the schema from a JSON file" do
          IOStreams.temp_file("schema", ".json") do |path|
            path.write(JSON.generate(schema))
            job.input_category.schema = path.to_s
            upload(".csv", csv)

            assert_equal records, output_records
          end
        end

        it "uploads in the mode of the category" do
          job.input_category.mode = :hash

          assert_equal 2, upload(".csv", csv)

          assert_equal ["Jack,21,2026-10-20", "Jill,22,2026-10-21"], input_records
          assert_equal records, output_records
        end

        it "parses every line when it is uploaded in :hash mode, so a value that is not valid uploads nothing" do
          assert_raises(IOStreams::Errors::InvalidValue) do
            upload(".csv", "Name,Age,Joined\nJack,21,2026-10-20\nJill,old,2026-10-21\n", stream_mode: :hash)
          end
          assert_equal 0, job.input.count
        end

        it "parses each line on the workers in :line mode, so a value that is not valid fails its slice" do
          assert_equal 2, upload(".csv", "Name,Age,Joined\nJack,21,2026-10-20\nJill,old,2026-10-21\n")
          job.save!

          assert_raises(IOStreams::Errors::InvalidValue) { job.perform_now }
          assert_equal 1, job.input.failed.count
        end

        it "raises for the :array mode" do
          error = assert_raises(ArgumentError) { upload(".csv", csv, stream_mode: :array) }
          assert_match(/cannot be uploaded in :array mode/, error.message)
        end
      end

      describe "without a schema" do
        let(:csv) { "Name,Age\nJack,21\n" }

        it "removes the letters that are not ASCII, as before" do
          upload(".csv", "Name\nJosé\n")

          assert_equal ["Jos"], input_records
        end

        it "uploads the lines of a file into a category in the :array mode" do
          job.input_category.mode = :array

          assert_equal 1, upload(".csv", csv)
          assert_equal %w[name age], job.input_category.columns
          assert_equal ["Jack,21"], input_records
          assert_equal [{"name" => "Jack", "age" => "21"}], output_records
        end

        it "uploads each row as an Array with stream_mode: :array" do
          assert_equal 1, upload(".csv", csv, stream_mode: :array)
          assert_equal %w[name age], job.input_category.columns
          assert_equal [%w[Jack 21]], input_records
          assert_equal [{"name" => "Jack", "age" => "21"}], output_records
        end

        it "uploads each row as an Array with stream_mode: :array into a category in the :array mode" do
          job.input_category.mode = :array

          assert_equal 1, upload(".csv", csv, stream_mode: :array)
          assert_equal %w[name age], job.input_category.columns
          assert_equal [%w[Jack 21]], input_records
          assert_equal [{"name" => "Jack", "age" => "21"}], output_records
        end
      end

      describe "on_first" do
        it "is called with the first record of a category without a format, which is not uploaded" do
          job.input_category.format = nil
          first                     = nil
          count                     = upload(".txt", "\nhello\nworld\n", on_first: ->(record) { first = record })

          assert_equal "", first
          assert_equal 2, count
          assert_equal %w[hello world], input_records
        end

        it "is called with the first record of a file without a header row, which is not uploaded" do
          job.input_category.columns = %w[name age]
          first                      = nil
          count                      = upload(".csv", "Jack,21\nJill,22\n", on_first: ->(record) { first = record })

          assert_equal "Jack,21", first
          assert_equal 1, count
          assert_equal ["Jill,22"], input_records
        end
      end
    end
  end
end

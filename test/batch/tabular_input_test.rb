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

        describe "validate_rows" do
          let(:invalid) { "Name,Age,Joined\nJack,21,2026-10-20\nJill,old,2026-10-21\n" }

          it "parses every line when it is uploaded, so a value that is not valid uploads nothing" do
            assert_raises(IOStreams::Errors::InvalidValue) { upload(".csv", invalid, validate_rows: true) }
            assert_equal 0, job.input.count
          end

          it "uploads the lines as they are, which the workers parse" do
            assert_equal 3, upload(".csv", "\n#{csv}\n", validate_rows: true)

            assert_equal ["Jack,21,2026-10-20", "Jill,22,2026-10-21", ""], input_records
            assert_equal records, output_records
          end

          it "is read from the category" do
            job.input_category.validate_rows = true

            assert_raises(IOStreams::Errors::InvalidValue) { upload(".csv", invalid) }
          end

          it "is false on the upload, overriding the :hash mode of the category" do
            job.input_category.mode = :hash

            assert_equal 2, upload(".csv", invalid, validate_rows: false)
          end

          it "is false on the category, overriding its :hash mode" do
            job.input_category.mode          = :hash
            job.input_category.validate_rows = false

            assert_equal 2, upload(".csv", invalid)
          end

          it "is parsed in the :hash stream_mode, supplied as a String" do
            assert_raises(IOStreams::Errors::InvalidValue) { upload(".csv", invalid, stream_mode: "hash") }
          end

          it "cannot be supplied with stream_mode" do
            error = assert_raises(ArgumentError) { upload(".csv", csv, validate_rows: true, stream_mode: :line) }
            assert_match(/either validate_rows:, or the deprecated stream_mode:/, error.message)
          end
        end
      end

      describe "without a schema" do
        it "removes the letters that are not ASCII, as before" do
          upload(".csv", "Name\nJosé\n")

          assert_equal ["Jos"], input_records
        end

        describe "validate_rows" do
          it "parses every line after the header row when it is uploaded, uploading the lines as they are" do
            assert_equal 3, upload(".csv", "\nName,Age\nJack,21\n\nJill,22\n", validate_rows: true)

            assert_equal %w[name age], job.input_category.columns
            assert_equal ["Jack,21", "", "Jill,22"], input_records
            assert_equal [{"name" => "Jack", "age" => "21"}, {"name" => "Jill", "age" => "22"}], output_records
          end

          it "uploads nothing when a line cannot be parsed" do
            csv = %(Name,Age\nJack,21\nJill,"22"x\n)
            assert_raises(CSV::MalformedCSVError) { upload(".csv", csv, validate_rows: true) }
            assert_equal 0, job.input.count
          end

          it "parses every line of a file without a header row, such as JSON" do
            job.input_category.format = :json

            assert_raises(StandardError) { upload(".json", %({"name":"Jack"}\n{"name":\n), validate_rows: true) }
            assert_equal 0, job.input.count
          end

          it "is not read from the :hash mode of the category, which 7.0 did not parse the lines in" do
            job.input_category.format = :json
            job.input_category.mode   = :hash

            assert_equal 2, upload(".json", %({"name":"Jack"}\n{"name":\n))
          end

          it "raises for a category without a format, which has no lines to parse" do
            job.input_category.format = nil

            error = assert_raises(ArgumentError) { upload(".txt", "hello\n", validate_rows: true) }
            assert_match(/validate_rows: needs a format/, error.message)
          end

          it "parses every line of a category in the :hash mode, after its header row" do
            job.input_category.mode          = :hash
            job.input_category.validate_rows = true

            assert_raises(CSV::MalformedCSVError) { upload(".csv", %(Name,Age\nJack,21\nJill,"22"x\n)) }
            assert_equal %w[name age], job.input_category.columns
          end
        end

        describe "the :hash stream_mode" do
          it "uploads the lines of a file in a format, reading its header row, and parses them first" do
            assert_equal 2, upload(".csv", "Name,Age\nJack,21\nJill,22\n", stream_mode: :hash)

            assert_equal %w[name age], job.input_category.columns
            assert_equal ["Jack,21", "Jill,22"], input_records
            assert_equal [{"name" => "Jack", "age" => "21"}, {"name" => "Jill", "age" => "22"}], output_records
          end

          it "uploads nothing when a line cannot be parsed" do
            assert_raises(CSV::MalformedCSVError) { upload(".csv", %(Name,Age\nJack,21\nJill,"22"x\n), stream_mode: :hash) }
            assert_equal 0, job.input.count
          end

          it "is read as a String" do
            assert_raises(CSV::MalformedCSVError) { upload(".csv", %(Name,Age\nJill,"22"x\n), stream_mode: "hash") }
          end

          it "reads each line of a category without a format into a Hash, in the format of the file name" do
            job.input_category.format = nil

            assert_equal 2, upload(".csv", "Name,Age\nJack,21\nJill,22\n", stream_mode: :hash)

            assert_equal [{"name" => "Jack", "age" => "21"}, {"name" => "Jill", "age" => "22"}], input_records
          end

          it "decides alone whether the lines are parsed, over the category's validate_rows" do
            job.input_category.validate_rows = true

            assert_equal 1, upload(".csv", %(Name,Age\nJill,"22"x\n), stream_mode: :line)
          end
        end

        it "reads the header row of a category in the :hash mode" do
          job.input_category.mode = :hash

          assert_equal 2, upload(".csv", "Name,Age\nJack,21\nJill,22\n")

          assert_equal ["Jack,21", "Jill,22"], input_records
          assert_equal [{"name" => "Jack", "age" => "21"}, {"name" => "Jill", "age" => "22"}], output_records
        end

        it "reads the header row of a category in the :array mode" do
          job.input_category.mode = :array

          assert_equal 2, upload(".csv", "Name,Age\nJack,21\nJill,22\n")

          assert_equal [{"name" => "Jack", "age" => "21"}, {"name" => "Jill", "age" => "22"}], output_records
        end

        it "reads the header row from the first Array of the :array stream_mode" do
          job.input_category.mode = :array

          assert_equal 2, upload(".csv", "Name,Age\nJack,21\nJill,22\n", stream_mode: :array)

          assert_equal %w[name age], job.input_category.columns
          assert_equal [%w[Jack 21], %w[Jill 22]], input_records
          assert_equal [{"name" => "Jack", "age" => "21"}, {"name" => "Jill", "age" => "22"}], output_records
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

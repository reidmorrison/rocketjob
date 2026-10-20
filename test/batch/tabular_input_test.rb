require_relative "../test_helper"

module Batch
  # How tabular input is read during upload, in each mode, and parsed by the workers, with the column restrictions
  # `allowed_columns`, `required_columns` and `skip_unknown`.
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
      let(:csv) { "Name,Age,Extra\nJack,21,x\nJill,22,y\n" }
      let(:json) { %({"Name":"Jack","age":21,"extra":"x"}\n{"name":"Jill","age":22}\n) }

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

      describe "mode" do
        it "uploads lines by default" do
          assert_equal 2, upload(".csv", csv)

          assert_equal %w[name age extra], job.input_category.columns
          assert_equal ["Jack,21,x", "Jill,22,y"], input_records
        end

        it "uploads arrays in :array mode" do
          job.input_category.mode = :array

          assert_equal 2, upload(".csv", csv)

          assert_equal %w[name age extra], job.input_category.columns
          assert_equal [%w[Jack 21 x], %w[Jill 22 y]], input_records
          assert_equal [
            {"name" => "Jack", "age" => "21", "extra" => "x"},
            {"name" => "Jill", "age" => "22", "extra" => "y"}
          ], output_records
        end

        it "reads the keys of the first record of a JSON file as the header row of its arrays in :array mode" do
          job.input_category.format = :json
          job.input_category.mode   = :array

          assert_equal 2, upload(".json", %({"name":"Jack","age":21}\n{"age":22,"name":"Jill"}\n))

          assert_equal %w[name age], job.input_category.columns
          assert_equal [["Jack", 21], ["Jill", 22]], input_records
          assert_equal [{"name" => "Jack", "age" => 21}, {"name" => "Jill", "age" => 22}], output_records
        end

        it "uploads hashes in :hash mode" do
          job.input_category.mode = :hash

          assert_equal 2, upload(".csv", csv)

          expected = [
            {"name" => "Jack", "age" => "21", "extra" => "x"},
            {"name" => "Jill", "age" => "22", "extra" => "y"}
          ]

          assert_equal expected, input_records
          assert_equal expected, output_records
        end

        it "uses stream_mode in place of the category's mode" do
          job.input_category.mode = :hash

          assert_equal 2, upload(".csv", csv, stream_mode: :array)

          assert_equal [%w[Jack 21 x], %w[Jill 22 y]], input_records
        end

        it "uploads arrays with supplied columns in :array mode" do
          job.input_category.mode    = :array
          job.input_category.columns = %w[name age extra]

          assert_equal 1, upload(".csv", "Jack,21,x\n")

          assert_equal [{"name" => "Jack", "age" => "21", "extra" => "x"}], output_records
        end

        it "reads the header row of arrays written to a block in :array mode" do
          job.input_category.mode = :array
          job.upload do |records|
            records << %w[Name Age]
            records << %w[Jack 21]
          end

          assert_equal %w[name age], job.input_category.columns
          assert_equal [{"name" => "Jack", "age" => "21"}], output_records
        end

        it "calls on_first with the header row in :array mode" do
          job.input_category.mode = :array
          header                  = nil
          upload(".csv", csv, on_first: ->(row) { header = row })

          assert_equal %w[Name Age Extra], header
        end
      end

      describe "a second file" do
        it "is not uploaded into a category that holds the header row of the first, which its lines are read by" do
          upload(".csv", csv)
          error = assert_raises(ArgumentError) { upload(".csv", "Name,City\nJoe,Boston\n") }

          assert_includes error.message, "already holds the header row of an uploaded file"
          assert_equal 2, job.record_count
          assert_equal ["Jack,21,x", "Jill,22,y"], input_records
        end

        it "is uploaded in :hash mode, in which each record keeps the columns of its own file" do
          job.input_category.mode = :hash
          upload(".csv", csv)
          upload(".csv", "Name,City\nJoe,Boston\n")

          assert_equal [{"name" => "Joe", "city" => "Boston"}], input_records.last(1)
          assert_equal 3, job.record_count
        end

        it "is uploaded into a category whose columns are set for files without a header row" do
          job.input_category.columns = %w[name age extra]
          upload(".csv", "Jack,21,x\n")
          upload(".csv", "Jill,22,y\n")

          assert_equal ["Jack,21,x", "Jill,22,y"], input_records
          refute job.input_category.header_uploaded
        end

        it "is not uploaded in :hash mode into a category that holds the header row of the first" do
          upload(".csv", csv)
          error = assert_raises(ArgumentError) { upload(".csv", "Name,City\nJoe,Boston\n", stream_mode: :hash) }

          assert_includes error.message, "already holds the header row of an uploaded file"
          assert_equal ["Jack,21,x", "Jill,22,y"], input_records
        end

        it "is uploaded after columns that were set are cleansed" do
          job.input_category.columns = ["First Name", "Age"]
          job.input_category.cleanse_header!
          upload(".csv", "Jack,21\n")
          upload(".csv", "Jill,22\n")

          assert_equal %w[first_name age], job.input_category.columns
          assert_equal ["Jack,21", "Jill,22"], input_records
          refute job.input_category.header_uploaded
        end

        it "of JSON is uploaded in :line mode" do
          job.input_category.format = :json
          upload(".json", %({"name":"Jack"}\n))
          upload(".json", %({"name":"Jill"}\n))

          assert_equal 2, job.record_count
        end
      end

      describe "a failed upload" do
        it "keeps neither the header row it read nor its records, so the file can be uploaded again" do
          job.input_category.columns = nil
          assert_raises(RuntimeError) do
            job.upload do |io|
              io << "Name,Age,Extra"
              io << "Jack,21,x"
              raise "upload failed"
            end
          end

          assert_nil job.input_category.columns
          refute job.input_category.header_uploaded
          assert_equal 0, job.input.count

          upload(".csv", csv)

          assert_equal ["Jack,21,x", "Jill,22,y"], input_records
          assert_equal %w[name age extra], job.input_category.columns
        end

        it "restores the columns that were set for a file without a header row" do
          job.input_category.columns = ["First Name", "Age"]
          assert_raises(RuntimeError) do
            job.upload do |io|
              io << "Jack,21"
              raise "upload failed"
            end
          end

          assert_equal ["First Name", "Age"], job.input_category.columns
          refute job.input_category.header_uploaded
        end
      end

      describe "csv" do
        it "keeps a quoted value with a line break in one record, whatever the file name" do
          upload(".txt", %(name,note\nJack,"line one\nline two"\n))

          assert_equal [{"name" => "Jack", "note" => "line one\nline two"}], output_records
        end
      end

      describe "blank lines before the header row" do
        let(:csv) { "\n  \nName,Age\nJack,21\n" }

        it "skips them, and reads the header row after them" do
          assert_equal 1, upload(".csv", csv)

          assert_equal %w[name age], job.input_category.columns
          assert_equal [{"name" => "Jack", "age" => "21"}], output_records
        end

        it "skips them in :array mode" do
          job.input_category.mode = :array

          assert_equal 1, upload(".csv", csv)

          assert_equal %w[name age], job.input_category.columns
          assert_equal [{"name" => "Jack", "age" => "21"}], output_records
        end

        it "skips them with a schema" do
          job.input_category.schema = {"fields" => [{"name" => "name"}, {"name" => "age", "type" => "integer"}]}

          assert_equal 1, upload(".csv", csv)

          # Each slice carries the header row of its file, as it is in the file, rather than the category.
          assert_nil job.input_category.columns
          assert_equal %w[Name Age], job.input.first.records.header
          assert_equal [{"name" => "Jack", "age" => 21}], output_records
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

      describe "fixed width" do
        before do
          job.input_category.format = :fixed
          job.input_category.schema = {
            "fields" => [{"name" => "name", "type" => "string", "width" => 10}, {"name" => "zip", "width" => 5}]
          }
        end

        it "reads ASCII" do
          upload(".txt", "Jack      54321\n")

          assert_equal [{"name" => "Jack", "zip" => "54321"}], output_records
        end

        it "uploads each line in :array mode, which the workers read by the schema" do
          job.input_category.mode = :array
          upload(".txt", "Jack      54321\nJill      12345\n")

          assert_equal ["Jack      54321", "Jill      12345"], input_records
          assert_equal [{"name" => "Jack", "zip" => "54321"}, {"name" => "Jill", "zip" => "12345"}], output_records
        end

        it "replaces non-printable characters with spaces, so that the columns stay in place" do
          upload(".txt", "Jack#{"\x00" * 6}54321\n")

          assert_equal [{"name" => "Jack", "zip" => "54321"}], output_records
        end

        it "rejects a character that is not ASCII, and uploads nothing" do
          with_file(".txt", "Jos\xE9      12345\n".b) do |file_name|
            assert_raises(Encoding::UndefinedConversionError) { job.upload(file_name) }
          end

          assert_equal 0, job.input.count
        end

        it "reads the encoding set on the path" do
          with_file(".txt", "Jos\xE9      12345\n".b) do |file_name|
            job.upload(IOStreams.path(file_name).encoding("ISO-8859-1:UTF-8"))
          end

          assert_equal [{"name" => "José", "zip" => "12345"}], output_records
        end

        it "reads UTF-8 whose sizes count characters, when set on the path" do
          with_file(".txt", "José      12345\n") do |file_name|
            job.upload(IOStreams.path(file_name).encoding("UTF-8"))
          end

          assert_equal [{"name" => "José", "zip" => "12345"}], output_records
        end

        it "replaces characters that are not ASCII when the path supplies replace" do
          with_file(".txt", "Jos\xE9      12345\n".b) do |file_name|
            job.upload(IOStreams.path(file_name).encoding(replace: " "))
          end

          assert_equal [{"name" => "Jos", "zip" => "12345"}], output_records
        end

        it "uploads each line in :hash mode, after reading it, which the workers read by the schema" do
          job.input_category.mode = :hash
          upload(".txt", "Jack      54321\nJill      12345\n")

          assert_equal ["Jack      54321", "Jill      12345"], input_records
          assert_equal [{"name" => "Jack", "zip" => "54321"}, {"name" => "Jill", "zip" => "12345"}], output_records
        end

        it "calls on_first with the first line, which is not uploaded, since the file has no header row" do
          first = nil
          upload(".txt", "HEADER    00000\nJack      54321\n", on_first: ->(row) { first = row })

          assert_equal "HEADER    00000", first
          assert_equal ["Jack      54321"], input_records
        end

        it "fails a record whose integer column is not a number" do
          job.input_category.schema["fields"].last["type"] = "integer"
          upload(".txt", "Jack        N/A\n")

          assert_raises(IOStreams::Errors::InvalidValue) { output_records }
        end

        it "reads the fixed width layout supplied as the deprecated format_options" do
          job.input_category.schema         = nil
          job.input_category.format_options = {layout: [{size: 10, key: "name"}, {size: 5, key: "zip"}]}
          upload(".txt", "Jack      54321\n")

          assert_equal [{"name" => "Jack", "zip" => "54321"}], output_records
        end

        it "passes the records of a layout with Symbol keys to perform with those keys, as before v8" do
          job.input_category.schema         = nil
          job.input_category.format_options = {layout: [{size: 10, key: :name}, {size: 5, key: :zip, type: :integer}]}
          upload(".txt", "Jack      54321\n")
          records = []
          job.stub(:perform, ->(record) { records << record }) { job.perform_now }

          assert_equal [{name: "Jack", zip: 54_321}], records
        end
      end

      describe "schema" do
        let(:schema) do
          {
            "fields" => [
              {"name" => "name", "type" => "string"},
              {"name" => "age", "type" => "integer"},
              {"name" => "balance", "type" => "number"},
              {"name" => "joined", "type" => "date"}
            ]
          }
        end
        let(:typed) { {"name" => "Jack", "age" => 21, "balance" => BigDecimal("12.5"), "joined" => Date.new(2026, 10, 13)} }
        let(:people) { "name,age,balance,joined\nJack,21,12.50,2026-10-13\n" }

        before do
          job.input_category.schema = schema
        end

        it "passes typed values to perform" do
          upload(".csv", people)

          assert_equal [typed], output_records
        end

        it "matches the header row to the fields whatever its case and punctuation, and keeps it as it is" do
          upload(".csv", "Name,AGE,Balance,Joined\nJack,21,12.50,2026-10-13\n")

          assert_equal %w[Name AGE Balance Joined], job.input.first.records.header
          assert_equal [typed], output_records
        end

        it "rejects a column that the schema does not list, and uploads nothing" do
          assert_raises(IOStreams::Errors::InvalidHeader) { upload(".csv", "name,age,balance,joined,extra\n") }
          assert_equal 0, job.input.count
        end

        it "skips the columns that a subset schema does not list" do
          job.input_category.schema = schema.merge("fieldsMatch" => "subset")
          upload(".csv", "extra,joined,balance,age,name\nx,2026-10-13,12.50,21,Jack\n")

          assert_equal [typed], output_records
        end

        it "uploads each line in :array mode, after parsing it" do
          job.input_category.mode = :array
          upload(".csv", "Name,AGE,Balance,Joined\nJack,21,12.50,2026-10-13\n")

          assert_equal ["Jack,21,12.50,2026-10-13"], input_records
          assert_equal [typed], output_records
        end

        it "uploads each line in :hash mode, after parsing it, so that a date reaches perform as a date" do
          job.input_category.mode = :hash
          upload(".csv", people)

          assert_equal ["Jack,21,12.50,2026-10-13"], input_records
          assert_equal [typed], output_records
        end

        it "rejects a value that is not valid in :hash mode, and uploads nothing" do
          job.input_category.mode = :hash
          assert_raises(IOStreams::Errors::InvalidValue) { upload(".csv", "#{people}Jill,x,1,2026-10-13\n") }

          assert_equal 0, job.input.count
          assert_equal 0, job.record_count.to_i
        end

        it "uploads files whose columns are in another order into the same category" do
          job.input_category.schema = schema.merge("fieldsMatch" => "equal")
          upload(".csv", people)
          upload(".csv", "joined,name,balance,age\n2026-10-14,Jill,1.5,22\n")
          jill = {"name" => "Jill", "age" => 22, "balance" => BigDecimal("1.5"), "joined" => Date.new(2026, 10, 14)}

          assert_equal 2, job.record_count
          assert_equal [typed, jill], output_records
        end

        it "calls on_first with the header row, as it is in the file" do
          header = nil
          upload(".csv", "Name,AGE,Balance,Joined\nJack,21,12.50,2026-10-13\n", on_first: ->(row) { header = row })

          assert_equal %w[Name AGE Balance Joined], header
          assert_equal [typed], output_records
        end

        it "calls on_first with the header row of a file without rows" do
          header = nil

          assert_equal 0, upload(".csv", "Name,AGE,Balance,Joined\n", on_first: ->(row) { header = row })
          assert_equal %w[Name AGE Balance Joined], header
        end

        it "fails the record whose value is not valid, which is processed again once it is corrected" do
          upload(".csv", "#{people}Jill,x,1,2026-10-13\nBob,23,2,2026-10-15\n")
          job.save!
          job.start!
          job.rocket_job_work(RocketJob::Worker.new, false)
          slice = job.input.first

          assert_predicate job, :failed?
          assert_equal 2, slice.processing_record_number
          assert_equal "Jill,x,1,2026-10-13", slice.failed_record

          slice.replace_record(1, "Jill,22,1,2026-10-13")
          slice.save!
          job.retry!
          job.rocket_job_work(RocketJob::Worker.new, false)
          names = job.output.collect(&:to_a).flatten(1).collect { |record| record["name"] }

          assert_predicate job, :completed?
          assert_equal %w[Jack Jill Bob], names
        end

        it "reads a file without a header row" do
          job.input_category.schema = schema.merge("header" => false)
          upload(".csv", "Jack,21,12.50,2026-10-13\n")

          assert_equal [typed], output_records
        end

        it "reads the schema from a file" do
          IOStreams.temp_file("tabular_input_test", ".json") do |path|
            path.write(JSON.generate(schema))
            job.input_category.schema = path.to_s
            upload(".csv", people)
          end

          assert_equal [typed], output_records
        end
      end

      describe "column restrictions" do
        before do
          job.input_category.allowed_columns = %w[name age]
        end

        describe "csv" do
          it "rejects unknown columns" do
            assert_raises(IOStreams::Errors::InvalidHeader) { upload(".csv", csv) }
          end

          it "skips unknown columns" do
            job.input_category.skip_unknown = true
            upload(".csv", csv)

            assert_equal [{"name" => "Jack", "age" => "21"}, {"name" => "Jill", "age" => "22"}], output_records
          end

          it "applies them to a header row that is not cleansed" do
            job.input_category.header_cleanser = :none
            job.input_category.allowed_columns = %w[Name Age]
            job.input_category.skip_unknown    = true
            upload(".csv", csv)

            assert_equal %w[Name Age __rejected__Extra], job.input_category.columns
            assert_equal [{"Name" => "Jack", "Age" => "21"}, {"Name" => "Jill", "Age" => "22"}], output_records
          end

          it "applies them to supplied columns" do
            job.input_category.columns      = %w[name age extra]
            job.input_category.skip_unknown = true
            upload(".csv", "Jack,21,x\n")

            assert_equal [{"name" => "Jack", "age" => "21"}], output_records
          end

          it "rejects unknown supplied columns" do
            job.input_category.columns = %w[name age extra]

            assert_raises(IOStreams::Errors::InvalidHeader) { upload(".csv", "Jack,21,x\n") }
          end

          it "skips unknown columns in :hash mode" do
            job.input_category.mode         = :hash
            job.input_category.skip_unknown = true
            upload(".csv", csv)

            assert_equal [{"name" => "Jack", "age" => "21"}, {"name" => "Jill", "age" => "22"}], input_records
          end

          it "rejects unknown columns in :hash mode" do
            job.input_category.mode = :hash

            assert_raises(IOStreams::Errors::InvalidHeader) { upload(".csv", csv) }
          end
        end

        describe "json" do
          before do
            job.input_category.format = :json
          end

          it "skips unknown keys, and cleanses the others" do
            job.input_category.skip_unknown = true
            upload(".json", json)

            assert_equal [{"name" => "Jack", "age" => 21}, {"name" => "Jill", "age" => 22}], output_records
          end

          it "rejects unknown keys" do
            upload(".json", json)

            assert_raises(IOStreams::Errors::InvalidHeader) { output_records }
          end

          it "rejects a record without a required column" do
            job.input_category.allowed_columns  = nil
            job.input_category.required_columns = %w[extra]
            upload(".json", json)

            assert_raises(IOStreams::Errors::InvalidHeader) { output_records }
          end

          it "applies them when the format is detected from the file name" do
            job.input_category.format = :auto
            upload(".json", json)

            assert_equal :json, job.input_category.format
            assert_raises(IOStreams::Errors::InvalidHeader) { output_records }
          end

          it "are not applied when IOStreams.enforce_column_restrictions is false" do
            IOStreams.enforce_column_restrictions = false
            upload(".json", json)

            assert_equal [
              {"Name" => "Jack", "age" => 21, "extra" => "x"},
              {"name" => "Jill", "age" => 22}
            ], output_records
          ensure
            IOStreams.enforce_column_restrictions = true
          end
        end
      end
    end
  end
end

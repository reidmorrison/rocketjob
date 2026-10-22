require_relative "../test_helper"

module Batch
  # How tabular input is read during upload, in each mode, and parsed by the workers, with and without a schema.
  # Every file of a tabular format is uploaded in slices that each hold its header row, see IOStreams::Slice.
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
        it "uploads lines by default, in slices that hold the header row of the file, as it is" do
          assert_equal 2, upload(".csv", csv)

          assert_nil job.input_category.columns
          assert_equal %w[Name Age Extra], job.input.first.records.header
          assert_equal ["Jack,21,x", "Jill,22,y"], input_records
          assert_equal [
            {"name" => "Jack", "age" => "21", "extra" => "x"},
            {"name" => "Jill", "age" => "22", "extra" => "y"}
          ], output_records
        end

        it "uploads the slices of a file of slice_size rows, each of which holds the header row" do
          job.input_category.slice_size = 2

          assert_equal 3, upload(".csv", "#{csv}Joe,23,z\n")

          assert_equal [2, 1], job.input.collect(&:size)
          assert_equal([%w[Name Age Extra]] * 2, job.input.collect { |slice| slice.records.header })
        end

        it "raises for the :array mode, which v8 removed, and uploads nothing" do
          job.input_category.mode = :array

          error = assert_raises(ArgumentError) { upload(".csv", csv) }
          assert_equal "Input category main: mode: :array was removed in Rocket Job v8, use :line, which the workers " \
                       "parse, or :hash to parse the whole file when it is uploaded, see " \
                       "#{RocketJob::Category::Base::REMOVED_OPTIONS_GUIDE}", error.message
          assert_raises(ArgumentError) do
            job.upload do |records|
              records << "Name,Age"
            end
          end
          assert_equal 0, job.input.count
        end

        it "raises for the :array stream_mode" do
          job.input_category.mode = :hash

          error = assert_raises(ArgumentError) { upload(".csv", csv, stream_mode: :array) }
          assert_includes error.message, "Input category main: mode: :array was removed in Rocket Job v8"
        end

        it "processes the arrays of a file that Rocket Job 7 uploaded in :array mode" do
          job.input_category.columns = %w[name age extra]
          job.upload_slice([%w[Jack 21 x], %w[Jill 22 y]])

          assert_equal [
            {"name" => "Jack", "age" => "21", "extra" => "x"},
            {"name" => "Jill", "age" => "22", "extra" => "y"}
          ], output_records
        end

        it "parses each row in :hash mode, and uploads the lines, which the workers read into hashes" do
          job.input_category.mode = :hash

          assert_equal 2, upload(".csv", csv)

          assert_equal ["Jack,21,x", "Jill,22,y"], input_records
          assert_equal [
            {"name" => "Jack", "age" => "21", "extra" => "x"},
            {"name" => "Jill", "age" => "22", "extra" => "y"}
          ], output_records
        end

        it "rejects a row that cannot be parsed in :hash mode, and uploads nothing, which :line mode uploads" do
          malformed = %(#{csv}Joe,"23"x,z\n)
          job.input_category.mode = :hash

          assert_raises(CSV::MalformedCSVError) { upload(".csv", malformed) }
          assert_equal 0, job.input.count
          assert_equal 0, job.record_count.to_i

          assert_equal 3, upload(".csv", malformed, stream_mode: :line)
        end

        it "uploads hashes in :hash mode into a category without a format, read in the format of the file name" do
          job.input_category.format = nil
          job.input_category.mode   = :hash

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

          assert_equal 2, upload(".csv", csv, stream_mode: :line)

          assert_equal ["Jack,21,x", "Jill,22,y"], input_records
        end

        it "uploads every record of JSON in :hash mode, which has no header row, and keeps its keys" do
          job.input_category.format = :json
          job.input_category.mode   = :hash

          assert_equal 2, upload(".json", json)
          assert_nil job.input.first.records.header
          assert_equal [{"Name" => "Jack", "age" => 21, "extra" => "x"}, {"name" => "Jill", "age" => 22}], output_records
        end

        it "processes the lines of a file that Rocket Job 7 uploaded, by the header row that it kept in columns" do
          job.input_category.columns = %w[name age extra]
          job.upload_slice(["Jack,21,x", "Jill,22,y"])

          assert_equal [
            {"name" => "Jack", "age" => "21", "extra" => "x"},
            {"name" => "Jill", "age" => "22", "extra" => "y"}
          ], output_records
        end
      end

      describe "a second file" do
        it "is uploaded into the same category, in each mode, and each row is read by the header row of its file" do
          %i[line hash].each do |mode|
            job.input_category.mode = mode
            upload(".csv", csv)
            upload(".csv", "Name,City\nJoe,Boston\n")
          end

          assert_equal 6, job.record_count
          assert_equal [{"name" => "Joe", "city" => "Boston"}], output_records.last(1)
        end

        it "that fails keeps the records of the first" do
          upload(".csv", csv)
          assert_raises(RuntimeError) do
            job.upload do |io|
              io << "Name,City"
              io << "Joe,Boston"
              raise "upload failed"
            end
          end

          assert_equal 2, job.record_count
          assert_equal ["Jack,21,x", "Jill,22,y"], input_records
        end

        it "without a header row is uploaded into a category whose schema describes its columns" do
          job.input_category.schema = {"header" => false, "fields" => [{"name" => "name"}, {"name" => "age"}]}
          upload(".csv", "Jack,21\n")
          upload(".csv", "Jill,22\n")

          assert_equal [{"name" => "Jack", "age" => "21"}, {"name" => "Jill", "age" => "22"}], output_records
        end

        it "of JSON is uploaded in :line mode" do
          job.input_category.format = :json
          upload(".json", %({"name":"Jack"}\n))
          upload(".json", %({"name":"Jill"}\n))

          assert_equal 2, job.record_count
        end
      end

      describe "a failed upload" do
        it "keeps none of its records, so the file can be uploaded again" do
          assert_raises(RuntimeError) do
            job.upload do |io|
              io << "Name,Age,Extra"
              io << "Jack,21,x"
              raise "upload failed"
            end
          end

          assert_equal 0, job.input.count

          upload(".csv", csv)

          assert_equal ["Jack,21,x", "Jill,22,y"], input_records
          assert_nil job.input_category.columns
        end

        it "keeps a format of :auto and no file name, so that another file is read in its own format" do
          job.input_category.format = :auto
          assert_raises(ArgumentError) { upload(".psv", "name|age\nJack|21\n", unknown: true) }

          assert_equal :auto, job.input_category.format
          assert_nil job.input_category.file_name

          upload(".csv", csv)

          assert_equal :csv, job.input_category.format
          assert_equal ["Jack,21,x", "Jill,22,y"], input_records
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

          assert_equal %w[Name Age], job.input.first.records.header
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
          assert_equal %w[Name Age], job.input.first.records.header
          assert_equal [{"name" => "Jack", "age" => "21"}], output_records
        end
      end

      describe "without a schema" do
        it "rejects the options of reading lines, since the lines are read in the format of the category" do
          error = assert_raises(ArgumentError) { upload(".csv", csv, delimiter: "\r\n") }

          assert_equal "Input category main: :delimiter cannot be supplied when uploading a file in the :csv format, " \
                       "whose lines are read in it", error.message
          assert_equal 0, job.input.count
        end

        it "rejects a schema set on the path, since the workers read each slice without one" do
          with_file(".csv", csv) do |file_name|
            path  = IOStreams.path(file_name).schema({"fields" => [{"name" => "name"}]})
            error = assert_raises(ArgumentError) { job.upload(path) }

            assert_includes error.message, "Set the schema of the file uploaded into input category main on the category"
          end
          assert_equal 0, job.input.count
        end

        it "raises for a Hash written to the block of an upload, since the block writes the lines of a file" do
          error = assert_raises(ArgumentError) do
            job.upload do |records|
              records << {"name" => "Jack"}
            end
          end

          assert_includes error.message, "not a Hash"
          assert_equal 0, job.input.count
        end

        it "raises for an Array written to the block of an upload, which Rocket Job 7 read as a row" do
          error = assert_raises(ArgumentError) do
            job.upload do |records|
              records << %w[name age]
              records << %w[Jack 21]
            end
          end

          assert_includes error.message, "not a Array"
          assert_equal 0, job.input.count
        end

        it "does not read the lines that upload_slice uploads by the header row of a file uploaded before" do
          upload(".csv", csv)
          job.upload_slice(["Joe,23,z"])

          error = assert_raises(ArgumentError) { output_records }
          assert_includes error.message, "The tabular header columns _must_ be set"
        end

        it "uploads a Hash written to the block of an upload into a category without a format, as it is" do
          job.input_category.format = nil
          job.upload do |records|
            records << {"name" => "Jack"}
          end

          assert_equal [{"name" => "Jack"}], output_records
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

        it "uploads each line in :hash mode, which the workers read by the schema" do
          job.input_category.mode = :hash
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

        it "uploads the first line, since the file has no header row" do
          upload(".txt", "Jill      12345\nJack      54321\n")

          assert_equal ["Jill      12345", "Jack      54321"], input_records
        end

        it "fails a record whose integer column is not a number" do
          job.input_category.schema["fields"].last["type"] = "integer"
          upload(".txt", "Jack        N/A\n")

          assert_raises(IOStreams::Errors::InvalidValue) { output_records }
        end

        it "raises without a schema, which gives the width of each field" do
          job.input_category.schema = nil

          error = assert_raises(ArgumentError) { upload(".txt", "Jack      54321\n") }
          assert_includes error.message, "The :fixed format needs a schema"
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

        it "rejects the options of reading lines, since the lines are read in the format of the category" do
          job.input_category.format = :auto
          error = assert_raises(ArgumentError) { upload(".csv", people, delimiter: "\r\n") }

          assert_equal "Input category main: :delimiter cannot be supplied when uploading a file in the :csv format, " \
                       "whose lines are read in it", error.message
          assert_equal 0, job.input.count
          # The category is as it was, so that another file is read in its own format.
          assert_equal :auto, job.input_category.format
          assert_nil job.input_category.file_name
        end

        it "uploads the lines written to a block in the format of the file name, when the format is :auto" do
          job.input_category.format = :auto
          job.upload(file_name: "people.psv") do |records|
            records << "name|age|balance|joined"
            records << "Jack|21|12.50|2026-10-13"
          end

          assert_equal :psv, job.input_category.format
          assert_equal :psv, job.input.first.records.format
          assert_equal [typed], output_records
        end

        it "uploads the lines written to a block as CSV, when the format is :auto and there is no file name" do
          job.input_category.format = :auto
          job.upload do |records|
            records << "name,age,balance,joined"
            records << "Jack,21,12.50,2026-10-13"
          end

          assert_equal :csv, job.input_category.format
          assert_equal [typed], output_records
        end

        it "keeps a format of :auto when the block of the upload raises" do
          job.input_category.format = :auto
          assert_raises(RuntimeError) do
            job.upload(file_name: "people.psv") do |records|
              records << "name|age|balance|joined"
              raise "failed"
            end
          end

          assert_equal :auto, job.input_category.format
          assert_equal 0, job.input.count
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

        it "uploads nothing for a file with only a header row" do
          assert_equal 0, upload(".csv", "Name,AGE,Balance,Joined\n")
          assert_equal 0, job.input.count
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

        describe "lines written to a block" do
          let(:jill) { {"name" => "Jill", "age" => 22, "balance" => BigDecimal("1.5"), "joined" => Date.new(2026, 10, 14)} }

          it "are read after the header row written first" do
            count =
              job.upload do |records|
                records << ""
                records << "Name,AGE,Balance,Joined"
                records << "Jack,21,12.50,2026-10-13"
              end

            assert_equal 1, count
            assert_nil job.input_category.columns
            assert_equal %w[Name AGE Balance Joined], job.input.first.records.header
            assert_equal [typed], output_records
          end

          it "are read in slices that each hold the header row" do
            job.input_category.slice_size = 2
            job.upload do |records|
              records << "name,age,balance,joined"
              3.times do
                records << "Jack,21,12.50,2026-10-13"
              end
              records << "Jill,22,1.5,2026-10-14"
            end

            # Each slice holds `slice_size` rows after the header row, as for a file.
            sizes   = job.input.collect(&:size)
            headers = job.input.collect { |slice| slice.records.header }

            assert_equal 4, job.record_count
            assert_equal [2, 2], sizes
            assert_equal [%w[name age balance joined]] * 2, headers
            assert_equal [typed, typed, typed, jill], output_records
          end

          it "are read with one tabular, which reads the header row once" do
            job.input_category.slice_size = 2
            built = 0
            new   = IOStreams::Schema.method(:new)
            IOStreams::Schema.stub(:new, lambda { |descriptor|
              built += 1
              new.call(descriptor)
            }) do
              job.upload do |records|
                records << "name,age,balance,joined"
                9.times do
                  records << "Jack,21,12.50,2026-10-13"
                end
              end
            end

            assert_equal 1, built
            assert_equal 5, job.input.count
          end

          it "written before the block breaks out are uploaded" do
            job.upload do |records|
              records << "name,age,balance,joined"
              records << "Jack,21,12.50,2026-10-13"
              break
            end

            assert_equal ["Jack,21,12.50,2026-10-13"], input_records
            assert_equal %w[name age balance joined], job.input.first.records.header
          end

          it "can follow a file in the same category" do
            upload(".csv", people)
            job.upload do |records|
              records << "name,age,balance,joined"
              records << "Jill,22,1.5,2026-10-14"
            end

            assert_equal [typed, jill], output_records
          end

          it "with only a header row upload nothing" do
            assert_equal(0, job.upload { |records| records << "Name,AGE,Balance,Joined" })
            assert_equal 0, job.input.count
          end

          it "of JSON have no header row" do
            job.input_category.format = :json
            job.upload do |records|
              records << %({"name":"Jack","age":21,"balance":"12.50","joined":"2026-10-13"})
              records << %({"name":"Jill","age":22,"balance":"1.5","joined":"2026-10-14"})
            end

            assert_equal [typed, jill], output_records
          end

          it "with a header row that does not match the schema upload nothing" do
            assert_raises(IOStreams::Errors::InvalidHeader) do
              job.upload do |records|
                records << "name,height"
                records << "Jack,2"
              end
            end

            assert_equal 0, job.input.count
          end

          it "raise for a record that is not a line" do
            error = assert_raises(ArgumentError) do
              job.upload do |records|
                records << {"name" => "Jack"}
              end
            end

            assert_includes error.message, "not a Hash"
            assert_equal 0, job.input.count
          end
        end
      end

      describe "on_first, which v8 removed" do
        let(:removed_message) do
          "on_first: was removed in Rocket Job v8: Rocket Job reads the header row itself, which the category's " \
            "schema checks, and to leave out the first record of a file without a header row, upload with a block " \
            "that writes the other lines, see https://rocketjob.reidmorrison.com/upgrading.html#replace-on_first"
        end

        it "raises when it is supplied to upload a file, before the file is read" do
          error = assert_raises(ArgumentError) { upload(".csv", csv, on_first: ->(_row) {}) }

          assert_equal removed_message, error.message
          assert_equal 0, job.input.count
          assert_nil job.input_category.columns
        end

        it "raises when it is supplied to upload a block, before the block is called" do
          called = false
          error  = assert_raises(ArgumentError) { job.upload(on_first: nil) { called = true } }

          assert_equal removed_message, error.message
          refute called
        end

        it "raises when it is supplied to upload a range" do
          error = assert_raises(ArgumentError) { job.upload(1..10, on_first: ->(_row) {}) }

          assert_equal removed_message, error.message
          assert_equal 0, job.input.count
        end
      end

      describe "the column options, which v8 removed" do
        let(:removed_message) do
          "were removed in Rocket Job v8, describe the columns of the file with the category's schema instead, see " \
            "#{RocketJob::Category::Base::REMOVED_OPTIONS_GUIDE}"
        end

        it "raise when they are supplied to upload" do
          error = assert_raises(ArgumentError) do
            upload(".csv", csv, allowed_columns: %w[name age], cleanse_header: false)
          end

          assert_equal "allowed_columns:, cleanse_header: #{removed_message}", error.message
          assert_equal 0, job.input.count
        end

        it "raise when they are nil, since IOStreams reads a nil cleanse_header as false" do
          error = assert_raises(ArgumentError) do
            upload(".csv", csv, stream_mode: :hash, cleanse_header: nil, skip_unknown: nil)
          end

          assert_equal "cleanse_header:, skip_unknown: #{removed_message}", error.message
          assert_equal 0, job.input.count
        end

        it "raise when a file is uploaded into a category saved with one, before the file is read" do
          job.input_category.attributes["skip_unknown"] = true

          error = assert_raises(ArgumentError) { upload(".csv", csv) }
          assert_equal "Input category main: skip_unknown was removed in Rocket Job v8, describe the columns of the " \
                       "file with the category's schema instead, see #{RocketJob::Category::Base::REMOVED_OPTIONS_GUIDE}",
                       error.message
          assert_raises(ArgumentError) do
            job.upload do |records|
              records << "Name,Age"
            end
          end
          assert_equal 0, job.input.count
        end

        it "raise when a worker reads a slice of a category saved with one" do
          upload(".csv", csv)
          job.input_category.attributes["allowed_columns"] = %w[name]

          error = assert_raises(ArgumentError) { output_records }
          assert_match(/\AInput category main: allowed_columns was removed in Rocket Job v8/, error.message)
        end

        it "raise in :hash mode, in which IOStreams would read the file with them" do
          error = assert_raises(ArgumentError) do
            upload(".csv", csv, stream_mode: :hash, required_columns: %w[name])
          end

          assert_match(/\Arequired_columns: was removed/, error.message)
        end

        describe "columns that no upload read" do
          before do
            job.input_category.columns = %w[name age extra]
          end

          it "raise before a file is read by them, in each mode" do
            [nil, :hash].each do |stream_mode|
              error = assert_raises(ArgumentError) { upload(".csv", "Jack,21,x\n", stream_mode: stream_mode) }

              assert_includes error.message, "Input category main holds columns that no upload read from a file. " \
                                             "Clear them when Rocket Job 7 copied them from an earlier run of a " \
                                             "scheduled job."
            end
            assert_equal 0, job.input.count
            assert_equal %w[name age extra], job.input_category.columns
          end

          it "raise before the lines written to a block are read by them" do
            assert_raises(ArgumentError) do
              job.upload do |records|
                records << "Jack,21,x"
              end
            end
            assert_equal 0, job.input.count
          end

          it "are not needed once they are cleared, since each slice holds the header row of its file" do
            job.input_category.columns = nil
            upload(".csv", csv)

            assert_nil job.input_category.columns
            assert_equal %w[Name Age Extra], job.input.first.records.header
          end
        end
      end

      describe "a schema in place of the column options" do
        it "rejects a file without a required field, as required_columns did" do
          job.input_category.schema = {
            "fieldsMatch" => "partial",
            "fields"      => [{"name" => "name"}, {"name" => "zip", "constraints" => {"required" => true}}]
          }

          assert_raises(IOStreams::Errors::InvalidHeader) { upload(".csv", csv) }
          assert_equal 0, job.input.count
        end

        it "reads the keys of JSON that it lists, whatever their case, and skips the others" do
          job.input_category.format = :json
          job.input_category.schema = {
            "fieldsMatch" => "partial",
            "fields"      => [{"name" => "name"}, {"name" => "age", "type" => "integer"}]
          }
          upload(".json", json)

          assert_equal [{"name" => "Jack", "age" => 21}, {"name" => "Jill", "age" => 22}], output_records
        end
      end
    end
  end
end

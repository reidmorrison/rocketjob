require_relative "../test_helper"

module Batch
  class CategoryTest < Minitest::Test
    describe RocketJob::Category::Input do
      describe "#header_uploaded" do
        it "is false for a category saved before v8, which did not record it" do
          category = Mongoid::Factory.from_db(RocketJob::Category::Input, {"name" => "main", "format" => "csv", "columns" => %w[name]})

          refute category.header_uploaded
        end
      end

      describe "the column options, which v8 removed" do
        let(:removed_message) do
          "were removed in Rocket Job v8, describe the columns of the file with the category's schema instead, see " \
            "#{RocketJob::Category::Base::REMOVED_OPTIONS_GUIDE}"
        end

        def saved_category(attributes)
          Mongoid::Factory.from_db(RocketJob::Category::Input, {"name" => "main", "format" => "csv"}.merge(attributes))
        end

        it "are not fields" do
          category = RocketJob::Category::Input.new

          %i[allowed_columns required_columns skip_unknown header_cleanser cleanse_header!].each do |name|
            refute_respond_to category, name
          end
        end

        it "are named when they are set to a value that had an effect" do
          properties = {
            allowed_columns:  %w[name],
            required_columns: %w[name],
            skip_unknown:     true,
            header_cleanser:  :none,
            columns:          %w[name]
          }

          assert_equal %w[allowed_columns required_columns skip_unknown header_cleanser columns],
                       RocketJob::Category::Input.removed_options(properties)
          assert_equal %w[skip_unknown header_cleanser],
                       RocketJob::Category::Input.removed_options("skip_unknown" => "true", "header_cleanser" => "none")
        end

        it "are left out when they are set to their defaults, which had no effect, as Mission Control saves them" do
          properties = {
            "allowed_columns" => [],
            "skip_unknown"    => "false",
            "header_cleanser" => "default",
            "columns"         => nil,
            "slice_size"      => 10
          }

          assert_empty RocketJob::Category::Input.removed_options(properties)
          assert_equal({"columns" => nil, "slice_size" => 10}, RocketJob::Category::Input.supported_properties(properties))
          assert_empty RocketJob::Category::Input.new.property_errors(properties)
        end

        it "raise when an input category is defined with them" do
          error = assert_raises(ArgumentError) do
            Class.new(RocketJob::Job) do
              include RocketJob::Batch

              input_category format: :csv, allowed_columns: %w[name zip], skip_unknown: true
            end
          end

          assert_equal "allowed_columns, skip_unknown #{removed_message}", error.message
        end

        it "do not raise when an input category is defined with their defaults" do
          job_class = Class.new(RocketJob::Job) do
            include RocketJob::Batch

            input_category format: :csv, skip_unknown: false, header_cleanser: :default
          end

          assert_equal :csv, job_class.new.input_category.format
        end

        it "are reported as an error of the properties of a Dirmon entry or an UploadFileJob" do
          category = RocketJob::Category::Input.new(format: :csv)

          assert_equal ["required_columns, header_cleanser #{removed_message}"],
                       category.property_errors("required_columns" => %w[name], "header_cleanser" => "none")
          assert_equal ["columns was removed in Rocket Job v8, describe the columns of the file with the category's " \
                        "schema instead, see #{RocketJob::Category::Base::REMOVED_OPTIONS_GUIDE}"],
                       category.property_errors("columns" => %w[name zip])
        end

        it "raise when merged into a category" do
          error = assert_raises(ArgumentError) do
            RocketJob::Category::Input.new.merge_properties("allowed_columns" => %w[name], "slice_size" => 10)
          end

          assert_match(/\Aallowed_columns was removed in Rocket Job v8/, error.message)
        end

        it "raise when a category saved with one reads its records, rather than reading them without it" do
          category = saved_category("columns" => %w[name zip], "allowed_columns" => %w[name], "skip_unknown" => true)

          error = assert_raises(ArgumentError) { category.parse("Jack,12345") }
          assert_equal "Input category main: allowed_columns, skip_unknown #{removed_message}", error.message
        end

        it "are ignored in a category saved with their defaults, as Rocket Job 7 saved every category" do
          category = saved_category(
            "columns"         => %w[name zip],
            "header_uploaded" => true,
            "skip_unknown"    => false,
            "header_cleanser" => "default"
          )

          assert_equal({"name" => "Jack", "zip" => "12345"}, category.parse("Jack,12345"))
        end
      end

      describe "#mode" do
        let(:array_message) do
          "mode: :array was removed in Rocket Job v8, use :line, which the workers parse, or :hash to parse the whole " \
            "file when it is uploaded, see #{RocketJob::Category::Base::REMOVED_OPTIONS_GUIDE}"
        end

        it "is :line or :hash, or :array in a category saved before v8, so that its next run can still be created" do
          assert_predicate RocketJob::Category::Input.new(mode: :hash), :valid?
          refute_predicate RocketJob::Category::Input.new(mode: :lines), :valid?

          category = Mongoid::Factory.from_db(RocketJob::Category::Input, {"name" => "main", "mode" => "array"})

          assert_predicate category, :valid?
          assert_predicate category.restart_copy, :valid?
        end

        it "raises for the :array mode when an input category is defined with it" do
          error = assert_raises(ArgumentError) do
            Class.new(RocketJob::Job) do
              include RocketJob::Batch

              input_category format: :csv, mode: :array
            end
          end

          assert_equal array_message, error.message
        end

        it "reports the :array mode in the properties of a Dirmon entry or an UploadFileJob, and keeps the others" do
          category = RocketJob::Category::Input.new

          assert_equal [array_message], category.property_errors("mode" => "array")
          assert_equal ["allowed_columns was removed in Rocket Job v8, describe the columns of the file with the " \
                        "category's schema instead, see #{RocketJob::Category::Base::REMOVED_OPTIONS_GUIDE}. " \
                        "#{array_message}"],
                       category.property_errors("mode" => :array, "allowed_columns" => %w[name])
          assert_equal({"mode" => "hash"}, RocketJob::Category::Input.supported_properties("mode" => "hash"))
          assert_equal :hash, category.merge_properties("mode" => "hash").mode
          assert_raises(ArgumentError) { category.merge_properties("mode" => "array") }
        end

        it "is the upload mode, unless another is supplied" do
          category = RocketJob::Category::Input.new(mode: :hash)

          assert_equal :hash, category.upload_mode
          assert_equal :line, category.upload_mode("line")
        end

        it "raises for the :array mode, which a category saved before v8 can hold" do
          category = Mongoid::Factory.from_db(RocketJob::Category::Input, {"name" => "main", "mode" => "array"})

          error = assert_raises(ArgumentError) { category.upload_mode }
          assert_equal "Input category main: #{array_message}", error.message
          error = assert_raises(ArgumentError) { category.upload_mode(:lines) }
          assert_equal "Input category main: the upload mode must be :line or :hash, not :lines", error.message
        end
      end

      describe "#tabular" do
        def deprecation_warnings(&)
          warnings = []
          Warning.stub(:warn, ->(message, category: nil) { warnings << message if category == :deprecated }, &)
          warnings
        end

        it "reads the header row that an upload stored without a deprecation warning" do
          category = RocketJob::Category::Input.new(format: :csv, columns: %w[first_name zip_code])
          record   = nil
          warnings = deprecation_warnings { record = category.parse_record("Jack,12345") }

          assert_equal({"first_name" => "Jack", "zip_code" => "12345"}, record)
          assert_empty warnings
        end

        it "reads the header row that Rocket Job 7 uploaded, which did not record that an upload read it" do
          category = Mongoid::Factory.from_db(
            RocketJob::Category::Input,
            {"name" => "main", "format" => "csv", "columns" => %w[first_name zip_code]}
          )

          assert_equal({"first_name" => "Jack", "zip_code" => "12345"}, category.parse_record("Jack,12345"))
        end

        it "reads the keys of the first JSON record that Rocket Job 7 read as the header row in the :array mode" do
          category = RocketJob::Category::Input.new(format: :json, columns: ["First Name", "zip"], header_uploaded: true)

          assert_equal({"First Name" => "Jack", "zip" => "12345"}, category.parse_record(%w[Jack 12345]))
        end

        it "raises for columns that are not a header row, which were set for a file without one before v8" do
          category = RocketJob::Category::Input.new(format: :csv, columns: %w[Name Zip])

          error = assert_raises(ArgumentError) { category.parse_record("Jack,12345") }
          assert_equal "Input category main holds columns that are not the header row of an uploaded file, so they " \
                       "are the columns of a file without a header row: columns was removed in Rocket Job v8, describe " \
                       "the columns of the file with the category's schema instead, see " \
                       "#{RocketJob::Category::Base::REMOVED_OPTIONS_GUIDE}", error.message
        end

        it "is built again after a field that it is built from is set" do
          category = RocketJob::Category::Input.new(format: :csv)
          tabular  = category.tabular
          category.columns = %w[name]

          refute_same tabular, category.tabular
        end
      end

      describe "#tabular" do
        it "returns tabular for the current settings" do
          schema = {
            "fields" => [{"name" => "action", "width" => 1}, {"name" => "date", "type" => "date", "width" => 10}],
            "width"  => "remainder"
          }
          category = RocketJob::Category::Input.new(format: :fixed, schema: schema)

          assert tabular = category.tabular
          assert_kind_of IOStreams::Tabular::Parser::Fixed, tabular.parser, tabular.parser.class.name
          # The schema reads each line into the values of its fields, by their types.
          assert_equal({"action" => "A", "date" => Date.new(2026, 10, 13)}, tabular.record_parse("A2026-10-13rest"))
        end

        it "reads a record without a header row by the schema, such as a line of JSON" do
          schema   = {"fields" => [{"name" => "first_name"}, {"name" => "age", "type" => "integer"}]}
          category = RocketJob::Category::Input.new(format: :json, schema: schema)

          assert_equal({"first_name" => "Jack", "age" => 21}, category.parse_record(%({"first_name":"Jack","age":"21"})))
        end

        it "uses the file_name when format is not set" do
          category = RocketJob::Category::Input.new(file_name: "sample.json")

          assert tabular = category.tabular
          assert_kind_of IOStreams::Tabular::Parser::Json, tabular.parser, tabular.parser.class.name
        end
      end

      describe "#parse_records" do
        let(:schema) { {"fields" => [{"name" => "name"}, {"name" => "age", "type" => "integer"}]} }

        def parse_records(category, records)
          parsed = []
          category.parse_records(records) { |record| parsed << record }
          parsed
        end

        it "reads the rows of a file by the header row that they carry, with the schema" do
          schema   = {"fieldsMatch" => "subset", "fields" => [{"name" => "first_name"}, {"name" => "age", "type" => "integer"}]}
          category = RocketJob::Category::Input.new(format: :csv, schema: schema)
          rows     = IOStreams::Slice.new(["21,12345,Jack", ""], header: ["Age", "Zip", "First Name"], format: :csv)

          assert_equal [{"first_name" => "Jack", "age" => 21}, nil], parse_records(category, rows)
        end

        it "reads the rows of a file without a schema by their header row, cleansed" do
          category = RocketJob::Category::Input.new(format: :csv)
          rows     = IOStreams::Slice.new(["Jack,21"], header: ["First Name", "AGE"], format: :csv)

          assert_equal [{"first_name" => "Jack", "age" => "21"}], parse_records(category, rows)
        end

        it "parses each other record on its own" do
          category = RocketJob::Category::Input.new(format: :csv, columns: %w[name age])

          assert_equal [{"name" => "Jack", "age" => "21"}, nil], parse_records(category, ["Jack,21", ""])
        end

        it "keeps the records of a category without a format" do
          assert_equal ["Jack,21", 5], parse_records(RocketJob::Category::Input.new, ["Jack,21", 5])
        end

        it "raises for a record that cannot be read, after yielding the records before it" do
          category = RocketJob::Category::Input.new(format: :csv, schema: schema)
          rows     = IOStreams::Slice.new(["Jack,21", "Jill,x"], header: %w[name age], format: :csv)
          parsed   = []

          assert_raises(IOStreams::Errors::InvalidValue) do
            category.parse_records(rows) { |record| parsed << record }
          end
          assert_equal [{"name" => "Jack", "age" => 21}], parsed
        end

        it "reads a schema held in a file once" do
          IOStreams.temp_file("input_test", ".json") do |path|
            path.write(JSON.generate(schema))
            category = RocketJob::Category::Input.new(format: :csv, schema: path.to_s)
            rows     = IOStreams::Slice.new(["Jack,21"], header: %w[name age], format: :csv)

            assert_equal [{"name" => "Jack", "age" => 21}], parse_records(category, rows)
            path.delete

            assert_equal [{"name" => "Jack", "age" => 21}], parse_records(category, rows)
          end
        end

        it "reads a schema held in a file again once it is set" do
          category = RocketJob::Category::Input.new(format: :csv, schema: "/does/not/exist/schema.json")
          rows     = IOStreams::Slice.new(["Jack,21"], header: %w[name age], format: :csv)

          assert_raises(Errno::ENOENT) { parse_records(category, rows) }
          category.schema = schema

          assert_equal [{"name" => "Jack", "age" => 21}], parse_records(category, rows)
        end

        it "reads a schema held in a file once for the tabular too, until the schema is set" do
          IOStreams.temp_file("input_test", ".json") do |path|
            path.write(JSON.generate(schema))
            category = RocketJob::Category::Input.new(format: :csv, schema: path.to_s)
            rows     = IOStreams::Slice.new(["Jack,21"], header: %w[name age], format: :csv)

            assert_equal [{"name" => "Jack", "age" => 21}], parse_records(category, rows)
            path.write("not json")
            category.file_name = "people.csv"
            category.format    = :csv

            assert_equal %w[name age], category.tabular.render_header.split(",")
            assert_equal [{"name" => "Jack", "age" => 21}], parse_records(category, rows)

            category.schema = path.to_s
            error = assert_raises(ArgumentError) { parse_records(category, rows) }
            assert_includes error.message, "Invalid schema in"
          end
        end

        it "raises ArgumentError for a schema file that is not a valid schema" do
          IOStreams.temp_file("input_test", ".json") do |path|
            path.write(JSON.generate("fields" => [{"name" => "name"}], "unknown" => 1))
            category = RocketJob::Category::Input.new(format: :csv, schema: path.to_s)

            error = assert_raises(ArgumentError) { category.tabular }
            assert_includes error.message, "Invalid schema in"
          end
        end
      end
    end
  end
end

require_relative "../test_helper"

module Batch
  class CategoryTest < Minitest::Test
    describe RocketJob::Category::Input do
      let(:mode_message) do
        "mode: was removed in Rocket Job v8: use validate_rows: true in place of mode: :hash, which parses each row " \
          "of a file in the category's format when it is uploaded, and remove mode: :array, since the workers parse " \
          "the lines of a file in the category's format, see " \
          "https://rocketjob.reidmorrison.com/upgrading.html#replace-the-hash-mode-with-validate_rows"
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
            "skip_unknown"    => false,
            "header_cleanser" => "default"
          )

          assert_equal({"name" => "Jack", "zip" => "12345"}, category.parse("Jack,12345"))
        end
      end

      describe "#validate_rows" do
        it "is false by default" do
          refute RocketJob::Category::Input.new.validate_rows
        end

        it "needs a format, whose rows it validates" do
          assert_predicate RocketJob::Category::Input.new(format: :csv, validate_rows: true), :valid?
          assert_predicate RocketJob::Category::Input.new(format: :auto, validate_rows: true), :valid?

          category = RocketJob::Category::Input.new(validate_rows: true)

          refute_predicate category, :valid?
          assert_equal ["Validate rows needs a format, whose rows it validates"], category.errors.full_messages
        end

        it "is reported in the properties of a Dirmon entry or an UploadFileJob without a format" do
          category = RocketJob::Category::Input.new

          assert_equal ["Validate rows needs a format, whose rows it validates"],
                       category.property_errors("validate_rows" => true)
          assert_empty category.property_errors("format" => "csv", "validate_rows" => true)
        end
      end

      describe "#upload_validates_rows?" do
        it "is the validate_rows of the category" do
          refute_predicate RocketJob::Category::Input.new(format: :csv), :upload_validates_rows?
          assert_predicate RocketJob::Category::Input.new(format: :csv, validate_rows: true), :upload_validates_rows?
        end

        it "is the validate_rows of the upload, unless it is nil" do
          category = RocketJob::Category::Input.new(format: :csv, validate_rows: true)

          refute category.upload_validates_rows?(false)
          assert category.upload_validates_rows?(nil)

          category.validate_rows = false

          assert category.upload_validates_rows?(true)
          assert RocketJob::Category::Input.new(format: :csv).upload_validates_rows?(true)
        end

        it "is false without a format, which has no rows to validate" do
          refute RocketJob::Category::Input.new.upload_validates_rows?(true)
        end
      end

      describe "a category that Rocket Job 7 saved with a mode" do
        def saved(attributes)
          Mongoid::Factory.from_db(RocketJob::Category::Input, {"name" => "main"}.merge(attributes))
        end

        it "reads the :hash mode as validate_rows: true in a format, which validate_rows replaces" do
          category = saved("format" => "csv", "mode" => "hash")

          assert category.validate_rows
          assert_predicate category, :upload_validates_rows?
          refute category.attributes.key?("mode")
          # Not changed, so that saving its job does not change it either.
          assert_empty category.changed & %w[mode validate_rows]
          assert_predicate category, :valid?
        end

        it "keeps the validate_rows that was saved with it" do
          category = saved("format" => "csv", "mode" => "hash", "validate_rows" => false)

          refute_nil category.validate_rows
          refute_predicate category, :upload_validates_rows?
        end

        it "drops the :hash mode without a format, and the :line mode, which had no effect" do
          [saved("mode" => "hash"), saved("format" => "csv", "mode" => "line")].each do |category|
            assert_nil category.validate_rows
            refute category.attributes.key?("mode")
            assert_predicate category, :valid?
          end
        end

        it "keeps the :array mode, so that its next run can still be created, and raises when it is uploaded into" do
          category = saved("mode" => "array")

          assert_predicate category, :valid?
          assert_predicate category.restart_copy, :valid?
          error = assert_raises(ArgumentError) { category.check_upload }
          assert_equal "Input category main: #{mode_message}", error.message
        end
      end

      describe "mode in the properties of a category" do
        it "raises for the :hash and :array modes when an input category is defined with one" do
          %i[hash array].each do |mode|
            error = assert_raises(ArgumentError) do
              Class.new(RocketJob::Job) do
                include RocketJob::Batch

                input_category format: :csv, mode: mode
              end
            end

            assert_equal mode_message, error.message
          end
        end

        it "reports the :hash and :array modes in the properties of a Dirmon entry or an UploadFileJob" do
          category = RocketJob::Category::Input.new

          assert_equal [mode_message], category.property_errors("mode" => "array")
          assert_equal [mode_message], category.property_errors("mode" => :hash)
          assert_equal ["allowed_columns was removed in Rocket Job v8, describe the columns of the file with the " \
                        "category's schema instead, see #{RocketJob::Category::Base::REMOVED_OPTIONS_GUIDE}. " \
                        "#{mode_message}"],
                       category.property_errors("mode" => "hash", "allowed_columns" => %w[name])
          assert_raises(ArgumentError) { category.merge_properties("mode" => "hash") }
        end

        it "drops the :line mode, which had no effect" do
          assert_equal({"format" => "csv"}, RocketJob::Category::Input.supported_properties("format" => "csv", "mode" => "line"))
          assert_empty RocketJob::Category::Input.new.property_errors("mode" => "line")
        end
      end

      describe "#check_upload" do
        it "accepts the validate_rows of an upload into a category with a format" do
          category = RocketJob::Category::Input.new(format: :csv)

          [nil, true, false].each do |validate_rows|
            assert_nil category.check_upload(validate_rows)
          end
        end

        it "raises for a validate_rows that is not true or false" do
          error = assert_raises(ArgumentError) { RocketJob::Category::Input.new(format: :csv).check_upload("yes") }
          assert_equal "Input category main: validate_rows: must be true or false, not \"yes\"", error.message
        end

        it "raises for validate_rows: true without a format, whose rows it would validate" do
          category = RocketJob::Category::Input.new

          assert_nil category.check_upload(false)
          error = assert_raises(ArgumentError) { category.check_upload(true) }
          assert_equal "Input category main: validate_rows: needs a format, whose rows it validates, such as :auto, " \
                       "which reads a file in the format of its file name", error.message
        end

        it "raises for the validate_rows of a category without a format, unless the upload supplies false" do
          category = RocketJob::Category::Input.new(validate_rows: true)

          assert_raises(ArgumentError) { category.check_upload }
          assert_nil category.check_upload(false)
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
          category = RocketJob::Category::Input.new(format: :json, columns: ["First Name", "zip"])

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

      describe "#slices?" do
        it "uploads the lines of a format of text in slices, also without a schema" do
          %i[csv psv json fixed].each do |format|
            assert_predicate RocketJob::Category::Input.new(format: format), :slices?, format
          end
        end

        it "uploads each record as it is without a format, or in a format whose rows are Ruby objects or not lines" do
          [nil, :hash, :array, :parquet].each do |format|
            refute_predicate RocketJob::Category::Input.new(format: format), :slices?, format.inspect
          end
        end

        it "reads a format of :auto from the file name, otherwise CSV" do
          assert_predicate RocketJob::Category::Input.new(format: :auto), :slices?
          assert_predicate RocketJob::Category::Input.new(format: :auto, file_name: "a.json"), :slices?
          refute_predicate RocketJob::Category::Input.new(format: :auto, file_name: "a.parquet"), :slices?
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

require_relative "../test_helper"

module Batch
  class CategoryTest < Minitest::Test
    describe RocketJob::Category::Input do
      describe "#cleanse_header!" do
        it "cleanses the header when cleanse_header is true" do
          category = RocketJob::Category::Input.new(columns: ["Name", "Address One", "zip code"])
          category.cleanse_header!

          assert_equal %w[name address_one zip_code], category.columns
        end

        it "does not cleanse the header when cleanse_header is false" do
          category = RocketJob::Category::Input.new(columns: ["Name", "Address One", "zip code"], header_cleanser: :none)
          category.cleanse_header!

          assert_equal ["Name", "Address One", "zip code"], category.columns
        end
      end

      describe "validation" do
        let(:schema) { {"fields" => [{"name" => "name"}]} }

        it "accepts the header row read from a file with a schema" do
          category = RocketJob::Category::Input.new(format: :csv, schema: schema, columns: %w[Name])

          assert_predicate category, :valid?
        end

        it "rejects the deprecated fields that a schema replaces" do
          category = RocketJob::Category::Input.new(
            format:           :csv,
            schema:           schema,
            allowed_columns:  %w[name],
            required_columns: %w[name],
            skip_unknown:     true,
            header_cleanser:  :none
          )

          refute_predicate category, :valid?
          assert_equal ["replaces allowed_columns, required_columns, skip_unknown, and header_cleanser, which cannot be set with it"],
                       category.errors[:schema]
        end

        it "rejects output columns with a schema" do
          category = RocketJob::Category::Output.new(format: :csv, schema: schema, columns: %w[name])

          refute_predicate category, :valid?
          assert_equal ["replaces columns, which cannot be set with it"], category.errors[:schema]
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

        it "matches the header row read from the file to the fields of the schema" do
          schema   = {"fieldsMatch" => "subset", "fields" => [{"name" => "first_name"}, {"name" => "age", "type" => "integer"}]}
          category = RocketJob::Category::Input.new(format: :csv, schema: schema, columns: ["Age", "Zip", "First Name"])

          refute_predicate category.tabular, :header?
          assert_equal({"first_name" => "Jack", "age" => 21}, category.parse_record("21,12345,Jack"))
        end

        it "applies the deprecated column restrictions, without a schema" do
          category = RocketJob::Category::Input.new(
            columns:          %w[abc def],
            format:           :csv,
            allowed_columns:  %w[name address zip_code],
            required_columns: %w[name address],
            skip_unknown:     false
          )

          assert tabular = category.tabular
          assert_equal %w[abc def], tabular.header.columns
          assert_equal %w[name address zip_code], tabular.header.allowed_columns
          assert_equal %w[name address], tabular.header.required_columns
          refute tabular.header.skip_unknown
        end

        it "uses the file_name when format is not set" do
          category = RocketJob::Category::Input.new(file_name: "sample.json")

          assert tabular = category.tabular
          assert_kind_of IOStreams::Tabular::Parser::Json, tabular.parser, tabular.parser.class.name
        end
      end
    end
  end
end

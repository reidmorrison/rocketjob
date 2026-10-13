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

      describe "#tabular" do
        it "returns tabular for the current settings" do
          schema = {
            "fields" => [{"name" => "action", "width" => 1}, {"name" => "date", "type" => "date", "width" => 10}],
            "width"  => "remainder"
          }
          category = RocketJob::Category::Input.new(
            columns:          %w[abc def],
            format:           :fixed,
            schema:           schema,
            allowed_columns:  %w[name address zip_code],
            required_columns: %w[name address],
            skip_unknown:     false
          )

          assert tabular = category.tabular
          assert_equal %w[abc def], tabular.header.columns
          assert_kind_of IOStreams::Tabular::Parser::Fixed, tabular.parser, tabular.parser.class.name
          # The schema splits each line into its fields.
          assert_equal({"action" => "A", "date" => "2026-10-13"}, tabular.parser.parse("A2026-10-13rest"))
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

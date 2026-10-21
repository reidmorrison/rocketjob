require_relative "../test_helper"

module Batch
  class CategoryTest < Minitest::Test
    describe RocketJob::Category::Input do
      describe "#schema" do
        let(:schema) { {"fields" => [{"name" => "name"}]} }

        it "cannot be set with the options that describe the columns without one" do
          category = RocketJob::Category::Input.new(
            format:           :csv,
            schema:           schema,
            allowed_columns:  %w[name],
            required_columns: %w[name],
            skip_unknown:     true,
            header_cleanser:  :none
          )

          refute_predicate category, :valid?
          assert_equal [
            "Schema replaces allowed_columns, required_columns, skip_unknown, and header_cleanser, which cannot be " \
            "set with it"
          ], category.errors.full_messages
        end

        it "can be set with the default skip_unknown and header_cleanser, and with the columns of its header row" do
          category = RocketJob::Category::Input.new(format: :csv, schema: schema, columns: %w[Name])

          assert_predicate category, :valid?
        end

        it "cannot be set with the :array mode" do
          category = RocketJob::Category::Input.new(format: :csv, schema: schema, mode: :array)

          refute_predicate category, :valid?
          assert_equal ["Mode cannot be :array with a schema, use :line or :hash"], category.errors.full_messages
        end
      end

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
          layout   = [
            {size: 1, key: :action},
            {size: 9, key: :date},
            {size: :remainder}
          ]
          category = RocketJob::Category::Input.new(
            columns:          %w[abc def],
            format:           :fixed,
            format_options:   {layout: layout},
            allowed_columns:  %w[name address zip_code],
            required_columns: %w[name address],
            skip_unknown:     false
          )

          assert tabular = category.tabular
          assert_equal %w[abc def], tabular.header.columns
          assert_kind_of IOStreams::Tabular::Parser::Fixed, tabular.parser, tabular.parser.class.name
          actual = tabular.parser.layout.columns.collect do |col|
            h       = {
              size: col.size == -1 ? :remainder : col.size
            }
            h[:key] = col.key if col.key
            h
          end

          assert_equal layout, actual
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

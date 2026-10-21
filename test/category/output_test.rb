require_relative "../test_helper"

module Batch
  class CategoryTest < Minitest::Test
    describe RocketJob::Category::Output do
      describe "#render_header" do
        it "renders the header when tabular" do
          category = RocketJob::Category::Output.new(format: :csv, columns: %w[name address zip_code])

          assert_equal category.render_header, %w[name address zip_code].to_csv.strip
        end

        it "returns nil when not tabular" do
          category = RocketJob::Category::Output.new

          assert_nil category.render_header
        end

        it "returns nil tabular, but does not need a header line" do
          category = RocketJob::Category::Output.new(format: :json)

          assert_nil category.render_header
        end

        it "renders the names of the fields of the schema" do
          category = RocketJob::Category::Output.new(format: :csv, schema: {"fields" => [{"name" => "login"}, {"name" => "zip"}]})

          assert_equal "login,zip", category.render_header
        end

        it "returns nil for a schema without a header row" do
          category = RocketJob::Category::Output.new(format: :csv, schema: {"header" => false, "fields" => [{"name" => "login"}]})

          assert_nil category.render_header
        end
      end

      describe "#schema" do
        let(:schema) do
          {
            "fields" => [
              {"name" => "login"},
              {"name" => "last_login", "type" => "datetime"},
              {"name" => "pay", "type" => "number", "decimals" => 2}
            ]
          }
        end

        it "renders each value in the text form of its type" do
          category = RocketJob::Category::Output.new(format: :csv, schema: schema)
          record   = {"login" => "jbloggs", "last_login" => Time.utc(2019, 2, 11, 5, 43, 20), "pay" => BigDecimal("12.5")}

          assert_equal "jbloggs,2019-02-11T05:43:20Z,12.50", category.tabular.render(record)
        end

        it "raises for a key that is not a field, unless fieldsMatch skips it" do
          category = RocketJob::Category::Output.new(format: :csv, schema: schema)

          assert_raises(IOStreams::Errors::InvalidHeader) { category.tabular.render({"login" => "x", "extra" => 1}) }

          category.schema = schema.merge("fieldsMatch" => "subset")

          assert_equal "x,,", category.tabular.render({"login" => "x", "extra" => 1})
        end

        it "cannot be set with columns" do
          category = RocketJob::Category::Output.new(format: :csv, schema: schema, columns: %w[login])

          refute_predicate category, :valid?
          assert_equal ["Schema replaces columns, which cannot be set with it"], category.errors.full_messages
        end
      end
    end
  end
end

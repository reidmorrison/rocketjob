require_relative "../test_helper"

module Batch
  class CategoryTest < Minitest::Test
    describe RocketJob::Category::Output do
      def schema(names)
        {"fields" => names.collect { |name| {"name" => name} }}
      end

      describe "#render" do
        it "renders a record in the format of the category" do
          category = RocketJob::Category::Output.new(format: :csv, schema: schema(%w[name zip_code]))

          assert_equal "Jack,12345", category.render("name" => "Jack", "zip_code" => "12345")
        end

        it "returns the record as it is without a format" do
          record = {"name" => "Jack"}

          assert_same record, RocketJob::Category::Output.new.render(record)
        end
      end

      describe "#tabular" do
        it "is built again after a field that it is built from is set" do
          category = RocketJob::Category::Output.new(format: :csv, schema: schema(%w[a b]))

          assert_equal "a,b", category.render_header
          category.schema = schema(%w[c d])

          assert_equal "c,d", category.render_header
          category.format = :psv

          assert_equal "c|d", category.render_header
        end
      end

      describe "#render_header" do
        it "renders the header when tabular" do
          category = RocketJob::Category::Output.new(format: :csv, schema: schema(%w[name address zip_code]))

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
      end

      describe "columns, which v8 removed" do
        it "is not a field" do
          refute_respond_to RocketJob::Category::Output.new, :columns
        end

        it "raises when an output category is defined with it" do
          error = assert_raises(ArgumentError) do
            Class.new(RocketJob::Job) do
              include RocketJob::Batch

              output_category format: :csv, columns: %w[name zip]
            end
          end

          assert_equal "columns was removed in Rocket Job v8, describe the columns of the file with the category's " \
                       "schema instead, see #{RocketJob::Category::Base::REMOVED_OPTIONS_GUIDE}", error.message
        end

        it "raises when an output category saved with it writes a record, rather than writing every key" do
          category = RocketJob::Category::Output.instantiate(
            "_id"     => BSON::ObjectId.new,
            "format"  => "json",
            "columns" => %w[name]
          )

          error = assert_raises(ArgumentError) { category.render({"name" => "Jack", "zip" => "12345"}) }
          assert_match(/\AOutput category main: columns was removed in Rocket Job v8/, error.message)
        end

        it "is left out of the properties when it is blank" do
          assert_equal({"format" => "csv"}, RocketJob::Category::Output.supported_properties("format" => "csv", "columns" => []))
        end
      end
    end
  end
end

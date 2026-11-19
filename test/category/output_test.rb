require_relative "../test_helper"

module Batch
  class CategoryTest < Minitest::Test
    describe RocketJob::Category::Output do
      def schema(names)
        {"fields" => names.collect { |name| {"name" => name} }}
      end

      describe "#output_records" do
        it "writes Hashes as the rows of a slice in the format of the category, after its header row" do
          category = RocketJob::Category::Output.new(format: :csv, schema: schema(%w[name zip_code]))
          records  = category.output_records([{"name" => "Jack", "zip_code" => "12345"}, {"zip_code" => "2", "name" => "J,ill"}])

          assert_equal %w[name zip_code], records.header
          assert_equal ["Jack,12345", "\"J,ill\",2"], records.rows
        end

        it "writes Arrays by position, against the fields of the schema" do
          category = RocketJob::Category::Output.new(format: :csv, schema: schema(%w[name zip_code]))

          assert_equal ["Jack,12345"], category.output_records([%w[Jack 12345]]).rows
        end

        it "writes a format without a header row, such as JSON" do
          category = RocketJob::Category::Output.new(format: :json)

          assert_equal [%({"name":"Jack"})], category.output_records([{"name" => "Jack"}]).rows
        end

        it "raises for a String in a format, which IOStreams writes from values" do
          category = RocketJob::Category::Output.new(format: :csv, schema: schema(%w[name]))

          error = assert_raises(ArgumentError) { category.output_records(["Jack"]) }
          assert_equal "Output category main: #perform must return a Hash or an Array for the :csv format, not a String",
                       error.message
        end

        it "returns the results as they are without a format" do
          results = ["Jack", {"name" => "Jill"}]

          assert_same results, RocketJob::Category::Output.new.output_records(results)
        end

        it "returns no records for no results" do
          category = RocketJob::Category::Output.new(format: :csv, schema: schema(%w[name]))

          assert_empty category.output_records([])
        end
      end

      describe "#header_line" do
        it "is the header row of the format, by the schema" do
          category = RocketJob::Category::Output.new(format: :csv, schema: schema(%w[name address zip_code]))

          assert_equal "name,address,zip_code", category.header_line
        end

        it "follows a change to the schema or the format" do
          category = RocketJob::Category::Output.new(format: :csv, schema: schema(%w[a b]))
          category.schema = schema(%w[c d])

          assert_equal "c,d", category.header_line
          category.format = :psv

          assert_equal "c|d", category.header_line
        end

        it "is nil without a format" do
          assert_nil RocketJob::Category::Output.new.header_line
        end

        it "is nil for a format without a header row" do
          assert_nil RocketJob::Category::Output.new(format: :json).header_line
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

          error = assert_raises(ArgumentError) { category.output_records([{"name" => "Jack", "zip" => "12345"}]) }
          assert_match(/\AOutput category main: columns was removed in Rocket Job v8/, error.message)
        end

        it "is left out of the properties when it is blank" do
          assert_equal({"format" => "csv"}, RocketJob::Category::Output.supported_properties("format" => "csv", "columns" => []))
        end
      end
    end
  end
end

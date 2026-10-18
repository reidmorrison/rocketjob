require_relative "../test_helper"

module Batch
  class CategoryTest < Minitest::Test
    describe RocketJob::Category::Output do
      describe "#render" do
        it "renders a record in the format of the category" do
          category = RocketJob::Category::Output.new(format: :csv, columns: %w[name zip_code])

          assert_equal "Jack,12345", category.render("name" => "Jack", "zip_code" => "12345")
        end

        it "returns the record as it is without a format" do
          record = {"name" => "Jack"}

          assert_same record, RocketJob::Category::Output.new.render(record)
        end
      end

      describe "#tabular" do
        it "is built again after a field that it is built from is set" do
          category = RocketJob::Category::Output.new(format: :csv, columns: %w[a b])

          assert_equal "a,b", category.render_header
          category.columns = %w[c d]

          assert_equal "c,d", category.render_header
          category.format = :psv

          assert_equal "c|d", category.render_header
        end
      end

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
      end
    end
  end
end

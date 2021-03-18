# require_relative "../test_helper"
#
# module Batch
#   class CategoryTest < Minitest::Test
#     describe RocketJob::Category::Output do
#       describe "#render_header" do
#         it "renders the header when tabular" do
#           category = RocketJob::Category::Output.new(format: :csv, columns: %w[name address zip_code])
#           assert_equal category.render_header, %w[name address zip_code].to_csv.strip
#         end
#
#         it "returns nil when not tabular" do
#           category = RocketJob::Category::Output.new
#           assert_nil category.render_header
#         end
#
#         it "returns nil tabular, but does not need a header line" do
#           category = RocketJob::Category::Output.new(format: :json)
#           assert_nil category.render_header
#         end
#       end
#     end
#   end
# end

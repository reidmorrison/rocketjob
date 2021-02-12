require_relative "../test_helper"

module Batch
  class CategoriesTest < Minitest::Test
    describe RocketJob::Batch::Categories do
      let(:categories) { RocketJob::Batch::Categories.new }
      let(:single_categories) { RocketJob::Batch::Categories.new(:other) }
      let(:two_categories) { RocketJob::Batch::Categories.new([:first, :second]) }
      let(:complex_categories) { RocketJob::Batch::Categories.new(first: { serializer: :compress }, second: { serializer: :encrypt }) }

      describe "initialize" do
        it "defaults to :main" do
          assert_equal [:main], categories.names
        end

        it "accepts a single category" do
          assert_equal [:other], single_categories.names
        end

        it "accepts an array of categories" do
          assert_equal [:first, :second], two_categories.names
        end

        it "accepts a hash of categories" do
          assert_equal [:first, :second], complex_categories.names
          assert_equal [:compress, :encrypt], complex_categories.collect(&:serializer)
        end

        it "accepts a Category instance" do
          category   = RocketJob::Batch::Category.new(name: :other, serializer: :compress)
          categories = RocketJob::Batch::Categories.new(category)
          assert_equal [:other], categories.names
        end
      end

      describe "#<<" do
        it "accepts a single category" do
          categories << :other
          assert_equal [:main, :other], categories.names
        end

        it "accepts an array of categories" do
          categories << [:first, :second]
          assert_equal [:main, :first, :second], categories.names
        end

        it "accepts a hash of categories" do
          categories << { first: { serializer: :compress }, second: { serializer: :encrypt } }
          assert_equal [:main, :first, :second], categories.names
        end

        it "accepts a Category instance" do
          category   = RocketJob::Batch::Category.new(name: :second, serializer: :compress)
          categories << category
          assert_equal [:main, :second], categories.names
        end
      end

      describe "#[]" do
        it "looks up by category name" do
          assert categories[:main]
        end

        it "looks up by string category name" do
          assert categories["main"]
        end

        it "raises and error when the category is not found" do
          assert_raises ArgumentError do
            categories[:blah]
          end
        end
      end

      describe "exist?" do
        it "looks up by category name" do
          assert categories.exist?(:main)
        end

        it "looks up by category string name" do
          assert categories.exist?("main")
        end

        it "is false when not found" do
          refute categories.exist?(:blah)
        end
      end

      describe "names" do
        it "returns category names" do
          assert [:first, :second], two_categories.names
        end
      end

      describe "mongoize" do
        it "serializes" do
          expected = [{"name"=>"first", "serializer"=>"compress"}, {"name"=>"second", "serializer"=>"encrypt"}]
          assert_equal expected, complex_categories.mongoize
        end
      end
    end
  end
end

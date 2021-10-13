require_relative "../test_helper"

module Batch
  class InputCategoriesTest < Minitest::Test
    class MainCategoryJob < RocketJob::Job
      include RocketJob::Batch

      def perform(record) end
    end

    class SingleCategoryJob < RocketJob::Job
      include RocketJob::Batch

      input_category slice_size: 2_000

      def perform(record) end
    end

    describe RocketJob::Batch::Categories do
      before do
        MainCategoryJob.destroy_all
        SingleCategoryJob.destroy_all
      end

      describe "#initialize" do
        it "default input category" do
          job = MainCategoryJob.new
          assert_equal 1, job.input_categories.size
          assert_equal :main, job.input_categories.first.name
          assert_equal :main, job.input_category.name
        end

        it "default slice_size" do
          job = MainCategoryJob.new
          assert_equal 1, job.input_categories.size
          assert_equal 100, job.input_categories.first.slice_size
          assert_equal 100, job.input_category.slice_size
        end

        it "custom slice_size" do
          job = SingleCategoryJob.new
          assert_equal 1, job.input_categories.size
          assert_equal 2_000, job.input_categories.first.slice_size
          assert_equal 2_000, job.input_category.slice_size
        end

        it "serializes" do
          job = SingleCategoryJob.new
          assert h = job.as_document
          assert_equal SingleCategoryJob.name, h["_type"]
          assert_equal 1, h["input_categories"].size
          assert_equal "main", h["input_categories"].first["name"]
        end
      end

      describe "#reload" do
        it "restores" do
          job = SingleCategoryJob.create
          job.reload
          assert job.is_a?(SingleCategoryJob)
          assert_equal 1, job.input_categories.size
          assert_equal :main, job.input_categories.first.name
        end
      end
    end
  end
end

require_relative "../test_helper"

module Batch
  class CategoriesTest < Minitest::Test
    class CategoriesJob < RocketJob::Job
      include RocketJob::Batch

      def perform(record)
        record
      end
    end

    describe RocketJob::Batch::Categories do
      before do
        CategoriesJob.destroy_all
      end

      after do
        CategoriesJob.destroy_all
      end

      # Builds a job from a raw (v5 era) persisted document, triggering the
      # after_initialize migration since the document is not a new record.
      def from_legacy(doc)
        doc = {"_id" => BSON::ObjectId.new}.merge(doc)
        Mongoid::Factory.from_db(CategoriesJob, doc)
      end

      describe "#input_category?" do
        it "is true for a defined category" do
          assert CategoriesJob.new.input_category?(:main)
        end

        it "is false for an unknown category" do
          refute CategoriesJob.new.input_category?(:nope)
        end

        it "accepts a string name" do
          assert CategoriesJob.new.input_category?("main")
        end
      end

      describe "#output_category?" do
        it "is false when no output category is defined" do
          refute CategoriesJob.new.output_category?(:main)
        end
      end

      describe "#input_category" do
        it "returns a supplied Category::Input unchanged" do
          category = RocketJob::Category::Input.new(name: :main)

          assert_same category, CategoriesJob.new.input_category(category)
        end

        it "raises when supplied an output category" do
          category = RocketJob::Category::Output.new(name: :main)
          assert_raises(ArgumentError) { CategoriesJob.new.input_category(category) }
        end

        it "raises for an unknown category name" do
          error = assert_raises(ArgumentError) { CategoriesJob.new.input_category(:missing) }
          assert_includes error.message, "Unknown Input Category"
        end
      end

      describe "#output_category" do
        it "returns a supplied Category::Output unchanged" do
          category = RocketJob::Category::Output.new(name: :main)

          assert_same category, CategoriesJob.new.output_category(category)
        end

        it "raises when supplied an input category" do
          category = RocketJob::Category::Input.new(name: :main)
          assert_raises(ArgumentError) { CategoriesJob.new.output_category(category) }
        end
      end

      describe "#merge_input_categories" do
        it "does nothing when blank" do
          job = CategoriesJob.new
          job.merge_input_categories(nil)

          assert_equal 100, job.input_category.slice_size
        end

        it "merges properties into the matching category" do
          job = CategoriesJob.new
          job.merge_input_categories([{"name" => "main", "slice_size" => 25}])

          assert_equal 25, job.input_category(:main).slice_size
        end

        it "defaults the category name to main" do
          job = CategoriesJob.new
          job.merge_input_categories([{"slice_size" => 17}])

          assert_equal 17, job.input_category(:main).slice_size
        end
      end

      describe "#merge_output_categories" do
        it "does nothing when blank" do
          job = CategoriesJob.new

          assert_nil job.merge_output_categories([])
        end
      end

      describe ".from_properties" do
        it "builds a plain job when no categories are supplied" do
          job = CategoriesJob.from_properties("description" => "hello")

          assert_equal "hello", job.description
        end

        it "merges supplied input category properties onto the defaults" do
          job = CategoriesJob.from_properties(
            "description"      => "with categories",
            "input_categories" => [{"name" => "main", "slice_size" => 42}]
          )

          assert_equal "with categories", job.description
          assert_equal 42, job.input_category(:main).slice_size
        end
      end

      describe "#rocketjob_categories_migrate" do
        it "leaves modern documents untouched" do
          job = from_legacy("input_categories" => [{"name" => "main", "serializer" => "none"}])

          assert_equal :main, job.input_category.name
        end

        it "migrates a compressed v5 job" do
          job = from_legacy(
            "input_categories" => [:main],
            "compress"         => true,
            "slice_size"       => 50
          )
          category = job.input_category(:main)

          assert_equal :compress, category.serializer
          assert_equal 50, category.slice_size
        end

        it "migrates an encrypted v5 job" do
          job      = from_legacy("input_categories" => [:main], "encrypt" => true)
          category = job.input_category(:main)

          assert_equal :encrypt, category.serializer
        end

        it "migrates tabular input attributes onto the main category" do
          job = from_legacy(
            "input_categories"     => [:main],
            "tabular_input_format" => :csv,
            "tabular_input_header" => %w[name value]
          )
          category = job.input_category(:main)

          assert_equal :csv, category.format
          assert_equal %w[name value], category.columns
        end

        it "migrates a non-main input category without tabular settings" do
          job = from_legacy(
            "input_categories"     => %i[main other],
            "tabular_input_format" => :csv
          )

          assert_equal :csv, job.input_category(:main).format
          assert_nil job.input_category(:other).format
        end

        it "builds an output category when collect_output was set" do
          job = from_legacy(
            "input_categories"      => [:main],
            "collect_output"        => true,
            "tabular_output_format" => :csv,
            "tabular_output_header" => %w[a b]
          )
          category = job.output_category(:main)

          assert_equal :csv, category.format
          assert_equal %w[a b], category.columns
        end

        it "does not build an output category when collect_output was false" do
          job = from_legacy("input_categories" => [:main], "collect_output" => false)

          assert_empty job.output_categories
        end

        it "migrates symbol output categories" do
          job = from_legacy(
            "input_categories"  => [:main],
            "output_categories" => %i[main extra],
            "collect_output"    => true
          )

          assert_equal %i[main extra], job.output_categories.collect(&:name)
        end
      end
    end
  end
end

require_relative "../test_helper"

module Batch
  class CategoriesTest < Minitest::Test
    class CategoriesJob < RocketJob::Job
      include RocketJob::Batch

      def perform(record)
        record
      end
    end

    class OutputCategoriesJob < RocketJob::Job
      include RocketJob::Batch

      output_category format: :csv

      def perform(record)
        record
      end
    end

    class CallbackCategoriesJob < RocketJob::Job
      include RocketJob::Batch

      input_category format: :csv, columns: %w[name zip]
      output_category format: :csv, columns: %w[name zip]

      field :seen, type: Array, default: []

      before_perform { seen << @rocket_job_input.class.name }
      after_perform { seen << @rocket_job_output.class.name }

      def perform(record)
        record
      end
    end

    class ParentCategoriesJob < RocketJob::Job
      include RocketJob::Batch

      input_category slice_size: 10
      output_category format: :csv

      def perform(record)
        record
      end
    end

    class ChildCategoriesJob < ParentCategoriesJob
      input_category name: :other
      input_category slice_size: 5
      output_category name: :errors
    end

    describe RocketJob::Batch::Categories do
      before do
        CategoriesJob.destroy_all
      end

      describe "#display_attributes" do
        it "shows the file name of each category without its credentials" do
          job = CategoriesJob.new
          job.input_category.file_name = "sftp://user:secret@sftp.example.org/in/file.csv"
          attrs = job.display_attributes

          assert_equal "sftp://sftp.example.org/in/file.csv", attrs["input_categories"].first["file_name"]
          assert_equal "sftp://user:secret@sftp.example.org/in/file.csv", job.input_category.file_name.to_s
        end
      end

      describe ".display_properties" do
        it "shows the file name of each category without its credentials" do
          properties = CategoriesJob.display_properties(
            "input_categories"  => [{"format" => "csv", "file_name" => "sftp://user:secret@sftp.example.org/in.csv"}],
            "output_categories" => [{"file_name" => "sftp://user:secret@sftp.example.org/out.csv"}]
          )

          assert_equal [{"format" => "csv", "file_name" => "sftp://sftp.example.org/in.csv"}], properties["input_categories"]
          assert_equal [{"file_name" => "sftp://sftp.example.org/out.csv"}], properties["output_categories"]
        end
      end

      after do
        CategoriesJob.destroy_all
      end

      # Builds a job from a persisted document, as it is read from the database.
      def from_db(doc)
        doc = {"_id" => BSON::ObjectId.new}.merge(doc)
        Mongoid::Factory.from_db(CategoriesJob, doc)
      end

      describe "parsing and rendering records" do
        it "parses and renders without perform callbacks of its own" do
          assert_empty CategoriesJob._perform_callbacks.to_a
          assert_empty OutputCategoriesJob._perform_callbacks.to_a
        end

        it "parses each record before the perform callbacks, and renders the result after them" do
          job = CallbackCategoriesJob.new
          job.upload_slice(["Jack,12345"])
          job.perform_now

          assert_equal %w[Hash Hash], job.seen
          assert_equal ["Jack,12345"], job.output.first.to_a
        ensure
          job&.cleanup!
        end
      end

      describe ".input_category" do
        it "does not change the input categories of the parent class" do
          parent = ParentCategoriesJob.defined_input_categories.collect { |c| [c.name, c.slice_size] }
          child  = ChildCategoriesJob.defined_input_categories.collect { |c| [c.name, c.slice_size] }

          assert_equal [[:main, 10]], parent
          assert_equal [[:main, 5], [:other, 100]], child
        end

        it "builds jobs of the parent class with its own input categories" do
          assert_equal [:main], ParentCategoriesJob.new.input_categories.collect(&:name)
          assert_equal %i[main other], ChildCategoriesJob.new.input_categories.collect(&:name)
        end

        it "returns the category" do
          klass = Class.new(CategoriesJob)

          assert_kind_of RocketJob::Category::Input, klass.input_category(name: :first)
          assert_kind_of RocketJob::Category::Input, klass.input_category(name: :second)
        end
      end

      describe ".output_category" do
        it "does not change the output categories of the parent class" do
          assert_equal [:main], ParentCategoriesJob.defined_output_categories.collect(&:name)
          assert_equal %i[main errors], ChildCategoriesJob.defined_output_categories.collect(&:name)
        end
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

        it "builds a job with the defaults without properties, as a job that is not a batch job does" do
          job = CategoriesJob.from_properties(nil)

          assert_instance_of CategoriesJob, job
          assert_equal CategoriesJob.new.input_categories.collect(&:name), job.input_categories.collect(&:name)
        end

        it "merges supplied input category properties onto the defaults" do
          job = CategoriesJob.from_properties(
            "description"      => "with categories",
            "input_categories" => [{"name" => "main", "slice_size" => 42}]
          )

          assert_equal "with categories", job.description
          assert_equal 42, job.input_category(:main).slice_size
        end

        it "merges category properties whose keys are Symbols onto the defaults" do
          job = OutputCategoriesJob.from_properties(
            description:       "with symbols",
            output_categories: [{name: :main, nils: true}]
          )

          assert_equal "with symbols", job.description
          assert job.output_category(:main).nils
          assert_equal :csv, job.output_category(:main).format
        end
      end

      describe ".property_errors" do
        it "is empty for valid category properties" do
          assert_empty OutputCategoriesJob.property_errors(
            "description"      => "valid",
            "input_categories" => [{"name" => "main", "encoding" => "Windows-1252"}],
            :output_categories => [{name: "main", encoding: "ISO-8859-1"}]
          )
        end

        it "names the category in each error" do
          errors = OutputCategoriesJob.property_errors(
            "input_categories"  => [{"slice_size" => nil, "blah" => 1}],
            "output_categories" => [{"name" => "main", "encoding" => "Nope"}]
          )

          assert_equal ["Input category main: Unknown property: blah",
                        "Output category main: Encoding \"Nope\" is not an encoding that Ruby knows, such as Windows-1252"],
                       errors
        end

        it "rejects a category that the job does not define" do
          assert_equal ["Output category main: Not defined by the job Batch::CategoriesTest::CategoriesJob, which defines: none"],
                       CategoriesJob.property_errors("output_categories" => [{"name" => "main"}])
          assert_equal ["Output category other: Not defined by the job Batch::CategoriesTest::OutputCategoriesJob, " \
                        "which defines: main"],
                       OutputCategoriesJob.property_errors("output_categories" => [{"name" => "other"}])
        end

        it "rejects categories that are not a list of properties" do
          [nil, "main", {"0" => {"name" => "main"}}, [%w[name main]]].each do |categories|
            assert_equal ["input_categories must be a list of the properties of each category, such as " \
                          "[{\"name\" => \"main\", \"encoding\" => \"Windows-1252\"}]"],
                         CategoriesJob.property_errors("input_categories" => categories),
                         categories.inspect
          end
        end

        it "does not build the job" do
          CategoriesJob.stub(:new, ->(*) { raise "built the job" }) do
            assert_empty CategoriesJob.property_errors("input_categories" => [{"slice_size" => 10}])
          end
        end
      end

      describe "a job saved before v8" do
        it "keeps the format_options of its categories when it is saved, so that a v7 worker can still read it" do
          job = CategoriesJob.create!
          layout = {"layout" => [{"size" => 10, "key" => "name"}, {"size" => 5, "key" => "zip"}]}
          CategoriesJob.collection.update_one(
            {_id: job.id},
            {"$set" => {"input_categories.0.format" => "fixed", "input_categories.0.format_options" => layout}}
          )

          job = CategoriesJob.find(job.id)

          assert_equal layout, job.input_category.format_options
          assert_nil job.input_category.schema

          job.description = "Saved again"
          job.save!
          category = CategoriesJob.collection.find(_id: job.id).first["input_categories"].first

          assert_equal layout, category["format_options"]
          refute category.key?("schema")
        end
      end

      describe "a job read from the database" do
        it "reads its categories" do
          job = from_db("input_categories" => [{"name" => "main", "serializer" => "none"}])

          assert_equal :main, job.input_category.name
          assert_equal :none, job.input_category.serializer
        end

        it "saves a change to a category of a job that was read from the database" do
          job = CategoriesJob.find(CategoriesJob.create!.id)
          job.input_category.slice_size = 50
          job.save!

          assert_equal 50, CategoriesJob.find(job.id).input_category.slice_size
        end
      end
    end
  end
end

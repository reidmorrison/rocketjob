require_relative "test_helper"

class DeprecationTest < Minitest::Test
  class DeprecatedCategoryJob < RocketJob::Job
    include RocketJob::Batch

    def perform(record)
      record
    end
  end

  class SavedOptionsJob < RocketJob::Job
    include RocketJob::Batch

    self.destroy_on_complete = false

    input_category format: :csv
    output_category format: :csv

    def perform(record)
      record
    end
  end

  class BrokenCallbackJob < RocketJob::Job
    field :broken, type: Mongoid::Boolean, default: false

    after_find :read_broken

    def read_broken
      nil.no_such_method if broken
    end
  end

  describe RocketJob::Deprecation do
    # Returns [Array<String>] the deprecation warnings that Rocket Job reported while the block runs, with deprecation
    # warnings on. IOStreams' own warnings, which name a line of Rocket Job, are left out.
    def deprecation_warnings(enabled: true, &block)
      warnings = []
      previous = Warning[:deprecated]
      Warning[:deprecated] = enabled
      collect = lambda do |message, category: nil|
        warnings << message if category == :deprecated && message.include?("Rocket Job: ")
      end
      Warning.stub(:warn, collect, &block)
      warnings
    ensure
      Warning[:deprecated] = previous
    end

    describe ".warn" do
      it "names the line outside Rocket Job that used what is deprecated" do
        line     = __LINE__ + 1
        warnings = deprecation_warnings { RocketJob::Deprecation.warn("old is deprecated") }

        assert_equal ["#{__FILE__}:#{line}: warning: Rocket Job: old is deprecated\n"], warnings
      end

      it "names no line when every caller is a library, such as in a worker" do
        library  = File.join(Gem.loaded_specs["activesupport"].full_gem_path, "lib", "worker.rb")
        warnings = deprecation_warnings do
          # rubocop:disable-next Style/EvalWithLocation -- the code must appear to be in a file of a gem.
          eval("Thread.new { RocketJob::Deprecation.warn('old is deprecated') }.join", binding, library, 1)
        end

        assert_equal ["Rocket Job: old is deprecated\n"], warnings
      end

      it "reports nothing while deprecation warnings are off" do
        assert_empty(deprecation_warnings(enabled: false) { RocketJob::Deprecation.warn("old is deprecated") })
      end
    end

    describe "the :array upload mode" do
      it "warns at the line of the job class that defines an input category with it" do
        line     = __LINE__ + 1
        warnings = deprecation_warnings { Class.new(DeprecatedCategoryJob) { input_category format: :csv, mode: :array } }

        assert_equal 1, warnings.size
        assert warnings.first.start_with?("#{__FILE__}:#{line}: warning: Rocket Job: mode: :array is deprecated"),
               warnings.first
      end

      it "does not warn for the :line and :hash modes" do
        warnings = deprecation_warnings do
          Class.new(DeprecatedCategoryJob) do
            input_category name: :lines, format: :csv
            input_category format: :csv, mode: :hash
          end
        end

        assert_empty warnings
      end

      it "does not warn again for each job of the class" do
        job_class = nil
        warnings  = deprecation_warnings do
          job_class = Class.new(DeprecatedCategoryJob) { input_category format: :csv, mode: :array }
        end

        assert_equal 1, warnings.size
        assert_empty(deprecation_warnings { job_class.new })
      end

      it "does not warn for a category saved before v8 that is read back" do
        warnings = deprecation_warnings do
          RocketJob::Category::Input.instantiate("_id" => BSON::ObjectId.new, "format" => "csv", "mode" => "array")
        end

        assert_empty warnings
      end

      it "warns at the line that uploads a file with it" do
        job      = Class.new(DeprecatedCategoryJob) { input_category format: :csv }.new
        line     = __LINE__ + 2
        warnings = deprecation_warnings do
          job.upload(StringIO.new("name\nJack\n"), file_name: "people.csv", stream_mode: :array)
        end

        assert(warnings.any? { |w| w.start_with?("#{__FILE__}:#{line}: warning: Rocket Job: stream_mode: :array") },
               warnings.inspect)
      ensure
        job&.cleanup!
      end
    end

    describe "properties with a deprecated option" do
      it "warns when they build a job" do
        warnings = deprecation_warnings do
          DeprecatedCategoryJob.from_properties(
            "input_categories" => [{"name" => "main", "format" => "csv", "mode" => "array"}]
          )
        end

        assert_equal 1, warnings.size
        assert_includes warnings.first, "mode: :array is deprecated"
      end

      it "does not warn when they are validated" do
        properties = {"input_categories" => [{"name" => "main", "format" => "csv", "mode" => "array"}]}

        assert_empty(deprecation_warnings { DeprecatedCategoryJob.property_errors(properties) })
      end
    end

    describe "the deprecated options of saved properties" do
      it "are named by each category class, whether the keys are Strings or Symbols" do
        assert_equal %w[mode], RocketJob::Category::Input.deprecated_option_names(mode: :array)
        assert_equal %w[mode], RocketJob::Category::Input.deprecated_option_names("mode" => "array")
        assert_equal %w[mode], RocketJob::Category::Input.new(mode: :array).deprecated_option_names
        assert_empty RocketJob::Category::Input.deprecated_option_names("mode" => "line")
        assert_empty RocketJob::Category::Output.deprecated_option_names("format" => "csv")
      end

      it "are found by a batch job class in the properties of each of its categories" do
        properties = {
          input_categories:  [{name: :main, mode: :array}],
          output_categories: [{"name" => "main"}]
        }

        assert_equal({"input category main" => %w[mode]}, SavedOptionsJob.deprecated_options(properties))
        assert_empty RocketJob::Jobs::SimpleJob.deprecated_options({})
      end
    end

    describe ".saved_options" do
      let(:job_class_name) { SavedOptionsJob.name }

      before do
        RocketJob::Job.delete_all
        RocketJob::DirmonEntry.delete_all
      end

      after do
        RocketJob::Job.delete_all
        RocketJob::DirmonEntry.delete_all
      end

      def saved_job(state: :queued)
        job = SavedOptionsJob.new(state: state)
        yield(job)
        job.save!
        job
      end

      it "lists each category of a job that can still run that holds a deprecated option" do
        job = saved_job(state: :paused) do |saved|
          saved.input_category.mode = :array
        end

        assert_equal ["#{job_class_name} #{job.id} (paused): input category main: mode"],
                     RocketJob::Deprecation.saved_options
      end

      it "leaves out a job that cannot run again" do
        saved_job(state: :completed) do |saved|
          saved.input_category.mode = :array
        end

        assert_empty RocketJob::Deprecation.saved_options
      end

      it "lists the deprecated options of the job that a Dirmon entry creates" do
        entry = RocketJob::DirmonEntry.create!(
          name:           "Old mode",
          pattern:        "deprecation_test/*.csv",
          job_class_name: job_class_name,
          properties:     {input_categories: [{name: "main", mode: "array"}]}
        )

        assert_equal ["Dirmon entry \"Old mode\" #{entry.id}: input category main: mode"],
                     RocketJob::Deprecation.saved_options
      end

      it "lists the deprecated options of the job that an UploadFileJob creates" do
        upload_job = RocketJob::Jobs::UploadFileJob.create!(
          job_class_name:   job_class_name,
          upload_file_name: __FILE__,
          properties:       {input_categories: [{name: "main", mode: "array"}]}
        )

        assert_equal ["RocketJob::Jobs::UploadFileJob #{upload_job.id} (queued): input category main: mode"],
                     RocketJob::Deprecation.saved_options
      end

      it "lists a job whose class cannot be loaded" do
        id = BSON::ObjectId.new
        RocketJob::Job.collection.insert_one("_id" => id, "_type" => "NoSuchJob", "state" => "queued")

        assert_equal ["Job #{id}: its class cannot be loaded, so its options cannot be read"],
                     RocketJob::Deprecation.saved_options
      end

      it "lists a Dirmon entry whose job class cannot be loaded" do
        entry = RocketJob::DirmonEntry.create!(
          name:           "Renamed",
          pattern:        "deprecation_test/renamed/*.csv",
          job_class_name: job_class_name,
          properties:     {input_categories: [{name: "main", mode: "array"}]}
        )
        RocketJob::DirmonEntry.collection.update_one({_id: entry.id}, {"$set" => {"job_class_name" => "NoSuchJob"}})

        assert_equal [
          "Dirmon entry \"Renamed\" #{entry.id}: the class of the job that it creates cannot be loaded, so its options " \
          "cannot be read"
        ], RocketJob::Deprecation.saved_options
      end

      it "lists an UploadFileJob whose job class cannot be loaded" do
        upload_job = RocketJob::Jobs::UploadFileJob.create!(job_class_name: "NoSuchJob", upload_file_name: __FILE__)

        assert_equal [
          "RocketJob::Jobs::UploadFileJob #{upload_job.id} (queued): the class of the job that it creates cannot be " \
          "loaded, so its options cannot be read"
        ], RocketJob::Deprecation.saved_options
      end

      it "lists a job that raises when it is read with its error, and still lists the others" do
        broken = BrokenCallbackJob.create!(broken: true)
        job    = saved_job do |saved|
          saved.input_category.mode = :array
        end
        lines = RocketJob::Deprecation.saved_options

        assert_equal 2, lines.size
        assert lines.first.start_with?("Job #{broken.id}: cannot be read: NoMethodError: "), lines.first
        assert_equal "#{job_class_name} #{job.id} (queued): input category main: mode", lines.last
      end

      it "lists nothing for a job with a schema" do
        saved_job do |saved|
          saved.input_category.schema = {"fields" => [{"name" => "name"}]}
        end

        assert_empty RocketJob::Deprecation.saved_options
      end
    end
  end
end

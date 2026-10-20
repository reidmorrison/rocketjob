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

    describe "a category defined with a deprecated option" do
      it "warns at the line of the job class that defines it" do
        line     = __LINE__ + 2
        warnings = deprecation_warnings do
          Class.new(DeprecatedCategoryJob) { input_category format: :csv, allowed_columns: %w[name], skip_unknown: true }
        end

        assert_equal 1, warnings.size
        assert warnings.first.start_with?("#{__FILE__}:#{line}: warning: Rocket Job: "), warnings.first
        assert_includes warnings.first, "allowed_columns:, skip_unknown: are deprecated"
      end

      it "warns for each deprecated option of an input category" do
        options = {
          "columns"          => %w[name],
          "allowed_columns"  => %w[name],
          "required_columns" => %w[name],
          "skip_unknown"     => true,
          "header_cleanser"  => "none"
        }

        assert_equal options.keys, RocketJob::Category::Input.deprecated_column_options(options)
      end

      it "does not warn for the default values" do
        options = {
          "schema"          => {"fields" => [{"name" => "name"}]},
          "skip_unknown"    => false,
          "header_cleanser" => "default"
        }

        assert_empty RocketJob::Category::Input.deprecated_column_options(options)
      end

      it "warns for an input category's columns, with or without a schema" do
        assert_equal ["columns"], RocketJob::Category::Input.deprecated_column_options("columns" => %w[Name])
        assert_equal ["columns"], RocketJob::Category::Input.deprecated_column_options(
          "columns" => %w[Name], "schema" => {"fields" => [{"name" => "name"}]}
        )
      end

      it "warns for the columns of an output category" do
        warnings = deprecation_warnings { Class.new(DeprecatedCategoryJob) { output_category format: :csv, columns: %w[a] } }

        assert_equal 1, warnings.size
        assert_includes warnings.first, "columns: is deprecated, describe the columns of the file with schema: instead"
      end

      it "warns for format_options" do
        warnings = deprecation_warnings do
          Class.new(DeprecatedCategoryJob) do
            input_category format: :fixed, format_options: {layout: [{size: 10, key: :name}]}
          end
        end

        assert_equal 1, warnings.size
        assert_includes warnings.first, "format_options: is deprecated, use schema: instead"
      end

      it "does not warn for a category defined with a schema" do
        warnings = deprecation_warnings do
          Class.new(DeprecatedCategoryJob) do
            input_category format: :csv, schema: {"fields" => [{"name" => "name"}]}
            output_category format: :csv, schema: {"fields" => [{"name" => "name"}]}
          end
        end

        assert_empty warnings
      end

      it "does not warn again for each job of the class" do
        job_class = nil
        warnings  = deprecation_warnings do
          job_class = Class.new(DeprecatedCategoryJob) { input_category format: :csv, allowed_columns: %w[a] }
        end

        assert_equal 1, warnings.size
        assert_empty(deprecation_warnings { job_class.new })
      end

      it "does not warn for a category saved before v8 that is read back" do
        warnings = deprecation_warnings do
          RocketJob::Category::Input.instantiate(
            "_id"             => BSON::ObjectId.new,
            "format"          => "fixed",
            "format_options"  => {"layout" => [{"size" => 10, "key" => "name"}]},
            "allowed_columns" => %w[name]
          )
        end

        assert_empty warnings
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

    describe "upload options that describe the columns" do
      it "warns at the line that uploads a file with them" do
        job      = Class.new(DeprecatedCategoryJob) { input_category format: :csv }.new
        line     = __LINE__ + 2
        warnings = deprecation_warnings do
          job.upload(StringIO.new("name\nJack\n"), file_name: "people.csv", stream_mode: :hash, allowed_columns: %w[name])
        end
        rocket_job = warnings.grep(/Rocket Job:/)

        assert_equal 1, rocket_job.size, warnings.inspect
        assert rocket_job.first.start_with?("#{__FILE__}:#{line}: warning: Rocket Job: allowed_columns: is deprecated"),
               rocket_job.first
      ensure
        job&.cleanup!
      end

      it "does not warn for an option that is nil, which IOStreams ignores" do
        job      = Class.new(DeprecatedCategoryJob) { input_category format: :csv }.new
        warnings = deprecation_warnings do
          job.upload(StringIO.new("name\nJack\n"), file_name: "people.csv", stream_mode: :hash, allowed_columns: nil)
        end

        assert_empty warnings.grep(/Rocket Job:/), warnings.inspect
      ensure
        job&.cleanup!
      end
    end

    describe "properties with a deprecated option" do
      it "warns when they build a job" do
        warnings = deprecation_warnings do
          DeprecatedCategoryJob.from_properties(
            "input_categories" => [{"name" => "main", "format" => "csv", "allowed_columns" => %w[name]}]
          )
        end

        assert_equal 1, warnings.size
        assert_includes warnings.first, "allowed_columns: is deprecated"
      end

      it "does not warn when they are validated" do
        properties = {"input_categories" => [{"name" => "main", "format" => "csv", "allowed_columns" => %w[name]}]}

        assert_empty(deprecation_warnings { DeprecatedCategoryJob.property_errors(properties) })
      end
    end

    describe "the deprecated options of saved properties" do
      it "are named by each category class, whether the keys are Strings or Symbols" do
        assert_equal %w[allowed_columns format_options mode],
                     RocketJob::Category::Input.deprecated_option_names(
                       allowed_columns: %w[name], format_options: {layout: []}, mode: :array, skip_unknown: false
                     )
        assert_equal %w[columns], RocketJob::Category::Output.deprecated_option_names("columns" => %w[name])
        assert_empty RocketJob::Category::Input.deprecated_option_names("mode" => "line", "header_cleanser" => "default")
      end

      it "are found by a batch job class in the properties of each of its categories" do
        properties = {
          input_categories:  [{name: :main, required_columns: %w[name]}],
          output_categories: [{"name" => "main"}]
        }

        assert_equal({"input category main" => %w[required_columns]}, SavedOptionsJob.deprecated_options(properties))
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
        job = saved_job do |saved|
          saved.input_category.allowed_columns = %w[name]
          saved.input_category.skip_unknown    = true
          saved.output_category.columns        = %w[name]
        end

        assert_equal [
          "#{job_class_name} #{job.id} (queued): input category main: allowed_columns, skip_unknown",
          "#{job_class_name} #{job.id} (queued): output category main: columns"
        ], RocketJob::Deprecation.saved_options
      end

      it "lists the :array mode and format_options" do
        job = saved_job(state: :paused) do |saved|
          saved.input_category.mode           = :array
          saved.input_category.format_options = {layout: [{size: 5, key: "name"}]}
        end

        assert_equal ["#{job_class_name} #{job.id} (paused): input category main: format_options, mode"],
                     RocketJob::Deprecation.saved_options
      end

      it "leaves out a job that cannot run again" do
        saved_job(state: :completed) do |saved|
          saved.input_category.allowed_columns = %w[name]
        end

        assert_empty RocketJob::Deprecation.saved_options
      end

      it "leaves out the header row that an upload read from a file" do
        saved_job do |saved|
          saved.input_category.columns         = %w[name]
          saved.input_category.header_uploaded = true
        end

        assert_empty RocketJob::Deprecation.saved_options
      end

      it "lists the deprecated options of the job that a Dirmon entry creates" do
        entry = RocketJob::DirmonEntry.create!(
          name:           "Old columns",
          pattern:        "deprecation_test/*.csv",
          job_class_name: job_class_name,
          properties:     {input_categories: [{name: "main", allowed_columns: %w[name]}]}
        )

        assert_equal ["Dirmon entry \"Old columns\" #{entry.id}: input category main: allowed_columns"],
                     RocketJob::Deprecation.saved_options
      end

      it "lists the deprecated options of the job that an UploadFileJob creates" do
        upload_job = RocketJob::Jobs::UploadFileJob.create!(
          job_class_name:   job_class_name,
          upload_file_name: __FILE__,
          properties:       {input_categories: [{name: "main", header_cleanser: "none"}]}
        )

        assert_equal ["RocketJob::Jobs::UploadFileJob #{upload_job.id} (queued): input category main: header_cleanser"],
                     RocketJob::Deprecation.saved_options
      end

      it "lists a job whose class cannot be loaded" do
        id = BSON::ObjectId.new
        RocketJob::Job.collection.insert_one("_id" => id, "_type" => "NoSuchJob", "state" => "queued")

        assert_equal ["Job #{id}: its class cannot be loaded, so its options cannot be read"],
                     RocketJob::Deprecation.saved_options
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

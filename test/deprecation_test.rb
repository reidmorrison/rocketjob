require_relative "test_helper"

class DeprecationTest < Minitest::Test
  class DeprecatedCategoryJob < RocketJob::Job
    include RocketJob::Batch

    def perform(record)
      record
    end
  end

  describe RocketJob::Deprecation do
    # Returns [Array<String>] the deprecation warnings that Rocket Job reported while the block runs, with deprecation
    # warnings on.
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

      it "links to the upgrade guide for 7.1" do
        assert_equal "https://rocketjob.reidmorrison.com/upgrading.html#upgrading-to-v71",
                     RocketJob::Deprecation::UPGRADE_GUIDE
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

      it "names each deprecated option of an input category" do
        options = {
          "columns"          => %w[name],
          "allowed_columns"  => %w[name],
          "required_columns" => %w[name],
          "skip_unknown"     => true,
          "header_cleanser"  => "none"
        }

        assert_equal options.keys, RocketJob::Category::Input.deprecated_column_options(options)
      end

      it "does not name an input category's columns with a schema, nor the default values" do
        options = {
          "columns"         => %w[Name],
          "schema"          => {"fields" => [{"name" => "name"}]},
          "skip_unknown"    => false,
          "header_cleanser" => "default"
        }

        assert_empty RocketJob::Category::Input.deprecated_column_options(options)
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

      it "does not warn for a category defined with a schema, or in the :line or :hash mode" do
        warnings = deprecation_warnings do
          Class.new(DeprecatedCategoryJob) do
            input_category name: :lines, format: :csv
            input_category format: :csv, mode: :hash, schema: {"fields" => [{"name" => "name"}]}
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

      it "does not warn for a category saved before 7.1 that is read back" do
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

    describe "an upload with a deprecated option" do
      let(:job) { Class.new(DeprecatedCategoryJob) { input_category format: :csv }.new }

      after do
        job.cleanup!
      end

      it "warns at the line that uploads a file with the options that describe its columns" do
        # v7 reads the header row of a category with a format in :line mode only, so this one has none.
        job.input_category.format = nil
        line                      = __LINE__ + 2
        warnings                  = deprecation_warnings do
          job.upload(StringIO.new("name\nJack\n"), file_name: "people.csv", stream_mode: :hash, allowed_columns: %w[name])
        end

        assert_equal 1, warnings.size, warnings.inspect
        assert warnings.first.start_with?("#{__FILE__}:#{line}: warning: Rocket Job: allowed_columns: is deprecated"),
               warnings.first
      end

      it "does not warn for an upload without one" do
        assert_empty(deprecation_warnings { job.upload(StringIO.new("name\nJack\n"), file_name: "people.csv") })
      end
    end

    describe "the :array mode, which only a schema rules out" do
      it "does not warn for a category in the :array mode" do
        warnings = deprecation_warnings { Class.new(DeprecatedCategoryJob) { input_category format: :csv, mode: :array } }

        assert_empty warnings
      end

      it "does not warn for an upload in the :array mode" do
        job      = Class.new(DeprecatedCategoryJob) { input_category format: :csv }.new
        count    = nil
        warnings = deprecation_warnings do
          count = job.upload(StringIO.new("name\nJack\n"), file_name: "people.csv", stream_mode: :array)
        end

        assert_empty warnings
        assert_equal 1, count
        assert_equal %w[name], job.input_category.columns
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

      it "does not warn for the columns of an input category whose job class gives it a schema" do
        job_class = Class.new(DeprecatedCategoryJob) { input_category format: :csv, schema: {"fields" => [{"name" => "name"}]} }
        warnings  = deprecation_warnings do
          job_class.from_properties("input_categories" => [{"name" => "main", "columns" => %w[Name]}])
        end

        assert_empty warnings
      end

      it "does not warn when a Dirmon entry checks them" do
        entry = RocketJob::DirmonEntry.new(
          name:           "Deprecated",
          pattern:        "deprecation_test/*.csv",
          job_class_name: DeprecatedCategoryJob.name,
          properties:     {"input_categories" => [{"name" => "main", "format" => "csv", "allowed_columns" => %w[name]}]}
        )

        assert_empty(deprecation_warnings { entry.valid? })
      end
    end
  end
end

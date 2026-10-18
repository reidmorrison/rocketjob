module Compat
  # Scenario 11, the checks that do not process a job: whether each set of category properties, as a Dirmon entry or
  # an UploadFileJob holds them, is accepted by `.property_errors` (v8 only), by a Dirmon entry and by an
  # UploadFileJob, and the categories of the job that `.from_properties` builds from them, and how an input category
  # cleanses its own columns, see `Category::Input#cleanse_header!`.
  class Checks
    def initialize(cases)
      @cases = cases
    end

    # Returns [Hash] the outcome of each check, by its name.
    def run
      klass = JobFactory.define("CheckJob", input: {}, outputs: [{}], transform: nil)
      FileUtils.mkdir_p(Paths.result("files"))
      File.write(upload_file_name, "name\nJack\n")

      results = {"Category::Input#cleanse_header! with allowed_columns + skip_unknown" => cleanse_header}
      @cases.each_pair do |name, properties|
        results[name] = Capture.during("checks: #{name}") { check(klass, name, properties) }
      end
      results
    end

    private

    def check(klass, name, properties)
      result = {}
      # Only v8 has .property_errors.
      if klass.respond_to?(:property_errors)
        result["property_errors"] = value_of("property_errors") { klass.property_errors(properties) }
      end
      result["dirmon_entry_errors"]    = errors_of(dirmon_entry(klass, name, properties))
      result["upload_file_job_errors"] = errors_of(upload_file_job(klass, properties))
      job, error = Result.attempt("from_properties") { klass.from_properties(properties) }
      result["from_properties"] =
        error || {"categories" => Inspection.categories(job), "valid" => job.valid?, "errors" => Inspection.validation_errors(job)}
      result
    end

    def cleanse_header
      Capture.during("checks: cleanse_header!") do
        columns = value_of("cleanse_header!") do
          category = RocketJob::Category::Input.new(format: :csv, columns: ["First Name", "Zip-Code", "Extra"],
                                                    allowed_columns: %w[first_name zip_code], skip_unknown: true)
          category.cleanse_header!
          category.columns
        end
        {"columns" => columns}
      end
    end

    def dirmon_entry(klass, name, properties)
      RocketJob::DirmonEntry.new(name: "compat #{name}", pattern: "/tmp/compat/#{name.hash.abs}/*",
                                 job_class_name: klass.name, properties: properties)
    end

    def upload_file_job(klass, properties)
      RocketJob::Jobs::UploadFileJob.new(job_class_name: klass.name, properties: properties,
                                         upload_file_name: upload_file_name)
    end

    def upload_file_name
      Paths.result("files/x.csv")
    end

    # Returns [Array<String>|Hash] why the supplied document is not valid, or the error that validating it raised.
    def errors_of(document)
      value_of("valid?") do
        document.valid?
        document.errors.full_messages
      end
    end

    # Returns the value of the block, or the error that it raised.
    def value_of(step, &)
      value, error = Result.attempt(step, &)
      error || value
    end
  end
end

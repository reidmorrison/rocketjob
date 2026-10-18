module Compat
  # Runs a scenario of the matrix the way an application uses Rocket Job: defines its job class, builds its job,
  # uploads its data and saves the job, then processes it with #perform_now, after reloading it as a worker would when
  # the scenario says so, and downloads it, see Processing. Records each step in a Result, and stops at the first step
  # that raises.
  class Runner
    def initialize(scenario)
      @scenario = scenario
    end

    # Returns [Result] the outcome of the scenario.
    def run
      result = Result.new(id: @scenario.id, desc: @scenario.desc, definition: @scenario.to_h)
      Capture.during(@scenario.id) { @scenario.around { run_steps(result) } }
      result
    end

    private

    def run_steps(result)
      job = build(result)
      return if result.failed?

      upload(job, result)
      return if result.failed?

      result.step("save") { job.save! }
      return result[:validation_errors] = Inspection.validation_errors(job) if result.failed?

      job = reload(job, result) if @scenario.reload?
      Processing.new(job).perform(result) unless result.failed?
    end

    def build(result)
      klass = result.step("define") { @scenario.define_job("S_") }
      return if result.failed?

      job = result.step("build") { @scenario.build(klass) }
      result[:categories_built] = Inspection.categories(job) if job
      job
    end

    def upload(job, result)
      count            = result.step("upload") { @scenario.upload(job) }
      result[:upload]  = {
        "return"         => count,
        "record_count"   => job.record_count,
        "input_category" => Inspection.category(job.input_category)
      }
      result[:uploaded_records] = Inspection.uploaded_records(job)
    end

    # Returns [RocketJob::Job] the job as a worker loads it from MongoDB, rather than the instance that uploaded it.
    def reload(job, result)
      Capture.during("#{@scenario.id} (reloaded)") do
        result.step("reload") { RocketJob::Job.find(job.id) }
      end
    end
  end
end

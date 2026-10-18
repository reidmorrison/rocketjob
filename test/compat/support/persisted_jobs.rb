module Compat
  # Scenario 12: the jobs that v7 creates, uploads and saves without processing them, one copy for each way that they
  # are then processed, see COPIES, and the ids of each copy, which it keeps in persisted-ids.json in the results, so
  # that the processes of each version that follow find them.
  class PersistedJobs
    # Each copy, and how it is processed after v7 saved it:
    #   v7     by v7 with #perform_now, the baseline
    #   v8     by v8 with #perform_now, v8 reading the jobs that v7 saved
    #   mixed  loaded and saved by v8, see #touch, then processed by v7, as during a rolling upgrade
    #   v7w    by a v7 worker, see Processing.work
    #   v8w    by a v8 worker
    COPIES = %w[v7 v8 mixed v7w v8w].freeze
    IDS    = "persisted-ids.json".freeze

    def initialize(scenarios)
      @scenarios = scenarios
    end

    # (v7) Defines the job class of each scenario, then creates, uploads and saves each copy of its job, without
    # processing it. Returns [Array<Hash>] the outcome of each scenario.
    def create
      ids     = {}
      results = @scenarios.map do |scenario|
        Capture.during(scenario.id) do
          result = Result.new(id: scenario.id, desc: scenario.desc, definition: scenario.to_h)
          klass  = result.step("define") { scenario.define_job("") }
          ids[scenario.id] = klass ? COPIES.to_h { |copy| create_copy(scenario, klass, copy, result) } : {}
          result.to_h
        end
      end
      Environment.write(IDS, ids)
      results
    end

    # Loads the supplied copy of each job, then processes it with #perform_now and downloads it.
    def process(copy)
      each_job(copy) do |job, result|
        result[:class]         = job.class.name
        result[:loaded]        = Inspection.categories(job)
        result[:loaded_valid]  = Inspection.validation_errors(job)
        result[:stored_before] = Inspection.stored_categories(job.id)
        Processing.new(job).perform(result)
        result[:stored_after] = Inspection.stored_categories(job.id)
      end
    end

    # Processes the supplied copy of each job the way a server's worker does, see Processing.work.
    def work(copy)
      each_id(copy) do |id, result|
        Processing.work(id, result)
        result[:stored_after] = Inspection.stored_categories(id)
      end
    end

    # (v8) Loads the supplied copy of each job and saves it, as a v8 server or Mission Control would, without
    # processing it, so that a v7 process can then process it.
    #
    # `save!` writes only the fields that changed, which are none for a job that is only loaded, so the whole document
    # is then written as v8 holds it, with every field of v8 that has a default, the most that a v8 save can write.
    def touch(copy)
      each_job(copy) do |job, result|
        result[:loaded]        = Inspection.categories(job)
        result[:stored_before] = Inspection.stored_categories(job.id)
        result.step("save") do
          job.save!
          job.collection.find(_id: job.id).replace_one(job.as_document)
        end
        result[:validation_errors] = Inspection.validation_errors(job) if result.failed?
        result[:stored_after]      = Inspection.stored_categories(job.id)
      end
    end

    private

    # Returns [Array(String, String)] the copy and the id of its job, once it is created, uploaded and saved.
    def create_copy(scenario, klass, copy, result)
      job           = klass.new
      count, error  = Result.attempt("upload") { scenario.upload(job) }
      _, save_error = Result.attempt("save") { job.save! }
      result[copy]  = {
        "upload"           => {"return" => count, "record_count" => job.record_count},
        "uploaded_records" => Inspection.uploaded_records(job),
        "error"            => error || save_error,
        "saved_document"   => Inspection.stored_categories(job.id)
      }
      [copy, job.id.to_s]
    end

    # Yields the id of the supplied copy of each job, and its result, after defining its job class, so that MongoDB's
    # `_type` of the job names a class. Returns [Array<Hash>] the outcome of each scenario.
    def each_id(copy)
      ids = JSON.parse(File.read(Paths.result(IDS)))
      @scenarios.map do |scenario|
        Capture.during("#{scenario.id} (#{copy})") do
          result = Result.new(id: scenario.id, desc: scenario.desc, copy: copy)
          id     = ids.dig(scenario.id, copy)
          result[:job_id] = id
          yield(id, result) if result.step("define") { scenario.define_job("") } && id
          result.to_h
        end
      end
    end

    # Yields the supplied copy of each job, loaded from MongoDB, and its result.
    def each_job(copy)
      each_id(copy) do |id, result|
        job = result.step("find") { RocketJob::Job.find(id) }
        yield(job, result) if job
      end
    end
  end
end

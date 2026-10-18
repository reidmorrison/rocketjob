require "stringio"

module Compat
  # Processes a batch job the way a test or a console does, with #perform_now, or the way a server's worker does,
  # see .work, and downloads every output category of the job once it completed, recording in a Result what #perform
  # received, the state of the job, and the text of each download.
  class Processing
    # Processes the job with the supplied id the way a server's worker does: claims it, starts it and works on its
    # slices, see RocketJob::Worker#next_available_job, then downloads it when it completed.
    def self.work(id, result)
      worker                = RocketJob::Worker.new(id: 1, server_name: "compat")
      worker.current_filter = {_id: BSON::ObjectId.from_string(id)}
      job                   = result.step("next_available_job") { worker.next_available_job }
      result[:claimed]      = !job.nil?
      job.class.received.clear if job
      3.times do
        break unless job&.running?

        result.step("rocket_job_work") { job.rocket_job_work(worker, false) }
        job = result.step("find") { RocketJob::Job.find(id) }
      end
      job = result.step("find") { RocketJob::Job.find(id) }
      job ? new(job).record(result) : result
    end

    def initialize(job)
      @job = job
    end

    # Processes the job with #perform_now, then downloads it, unless that raised.
    def perform(result)
      @job.class.received.clear
      result.step("perform") { @job.perform_now }
      record(result)
    end

    # Records what #perform received and the state of the job, then downloads it when it completed, or why it is not
    # valid when it failed validation.
    def record(result)
      result[:received] = @job.class.received.dup
      result[:job]      = Inspection.state(@job)
      if result.failed?
        result[:validation_errors] = Inspection.validation_errors(@job) if result["error"]["class"].include?("Validations")
      elsif @job.completed?
        result[:download] = download
      end
      result
    end

    # Returns [Hash] the text of each output category of the job, downloaded to a StringIO, or the error that the
    # download raised.
    def download
      @job.output_categories.to_h do |category|
        io           = StringIO.new
        value, error = Result.attempt("download #{category.name}") { @job.download(io, category: category.name) }
        text         = io.string
        output       = {"encoding" => text.encoding.name, "text" => text.dup.force_encoding("UTF-8"), "return" => value}
        output["error"] = error if error
        [category.name.to_s, output]
      end
    end
  end
end

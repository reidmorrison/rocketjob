# Convert to and from CSV, JSON, xlsx, and PSV files.
#
# Example, Convert CSV file to JSON.
#   job = RocketJob::Jobs::ConversionJob.new
#   job.input_category.file_name  = "data.csv"
#   job.output_category.file_name = "data.json"
#   job.save!
#
# Example, Convert JSON file to PSV and compress it with GZip.
#   job = RocketJob::Jobs::ConversionJob.new
#   job.input_category.file_name  = "data.json"
#   job.output_category.file_name = "data.psv.gz"
#   job.save!
#
# Example, Read a CSV file that has been zipped from a remote website and the convert it to a GZipped json file.
#   job = RocketJob::Jobs::ConversionJob.new
#   job.input_category.file_name  = "https://example.org/file.zip"
#   job.output_category.file_name = "data.json.gz"
#   job.save!
#
module RocketJob
  module Jobs
    class ConversionJob < RocketJob::Job
      include RocketJob::Batch

      self.destroy_on_complete = false

      # Detects file extension for its type
      input_category format: :auto
      output_category format: :auto

      # Upload the file specified in `input_category.file_name` unless already uploaded.
      before_batch :upload, unless: :record_count

      # When the job completes it will write the result to `output_category.file_name`.
      after_batch :cleanup!, :download

      def perform(hash)
        hash
      end
    end
  end
end

module RocketJob
  module Jobs
    class PerformanceJob < RocketJob::Job
      include RocketJob::Batch

      # Define the job's default attributes
      self.description         = "Performance Test"
      self.priority            = 5
      self.destroy_on_complete = false

      input_category slice_size: 100
      output_category

      # No operation, just return the supplied line (record)
      def perform(line)
        line
      end
    end
  end
end

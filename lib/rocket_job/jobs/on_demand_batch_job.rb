# Job to dynamically perform ruby code on demand as a Batch,
#
# Often used for data correction or cleansing.
#
# Example: Iterate over all rows in a table:
#   code = <<-CODE
#     if user = User.find(row)
#       user.cleanse_attributes!
#       user.save(validate: false)
#     end
#   CODE
#   job  = RocketJob::Jobs::OnDemandBatchJob.new(code: code, description: 'cleanse users')
#   arel = User.unscoped.all.order('updated_at DESC')
#   job.upload_arel(arel)
#   job.save!
#
# Console Testing:
#   code = <<-CODE
#     if user = User.find(row)
#       user.cleanse_attributes!
#       user.save(validate: false)
#     end
#   CODE
#   job  = RocketJob::Jobs::OnDemandBatchJob.new(code: code, description: 'cleanse users')
#
#   # Run against a sub-set using a limit
#   arel = User.unscoped.all.order('updated_at DESC').limit(100)
#   job.upload_arel(arel)
#
#   # Run the subset directly within the console
#   job.perform_now
#   job.cleanup!
#
# By default output is not collected, call the method `#collect_output` to collect output.
#
# Example:
#   job = RocketJob::Jobs::OnDemandBatchJob(
#     description:              'Fix data',
#     code:                     code,
#     throttle_running_workers: 5,
#     priority:                 30
#   )
#   job.collect_output
#   job.save!
#
# Example: Move the upload operation into a before_batch.
#   upload_code = <<-CODE
#     arel = User.unscoped.all.order('updated_at DESC')
#     upload_arel(arel)
#   CODE
#
#   code = <<-CODE
#     if user = User.find(row)
#       user.cleanse_attributes!
#       user.save(validate: false)
#     end
#   CODE
#
#   RocketJob::Jobs::OnDemandBatchJob.create!(
#     upload_code: upload_code,
#     code:        code,
#     description: 'cleanse users'
#   )
module RocketJob
  module Jobs
    class OnDemandBatchJob < RocketJob::Job
      include RocketJob::Plugins::Cron
      include RocketJob::Plugins::Retry
      include RocketJob::Batch
      include RocketJob::Batch::Statistics

      self.priority            = 90
      self.description         = "On Demand Batch Job"
      self.destroy_on_complete = false
      self.retry_limit         = 0

      # Code that is performed against every row / record.
      field :code, type: String, user_editable: true, copy_on_restart: true

      # Optional code to execute before the batch is run.
      # Usually to upload data into the job.
      field :before_code, type: String, user_editable: true, copy_on_restart: true

      # Optional code to execute after the batch is run.
      # Usually to upload data into the job.
      field :after_code, type: String, user_editable: true, copy_on_restart: true

      # Data that is made available to the job during the perform.
      # Be sure to store key names only as Strings, not Symbols.
      field :data, type: Hash, default: {}, user_editable: true, copy_on_restart: true

      validates :code, presence: true
      validate :validate_code
      validate :validate_before_code
      validate :validate_after_code

      before_slice :load_perform_code
      before_batch :run_before_code
      after_batch :run_after_code

      # Shortcut for setting the slice_size
      def slice_size=(slice_size)
        input_category.slice_size = slice_size
      end

      # Add a new output category and collect output for it.
      def add_output_category(**args)
        self.output_categories << RocketJob::Category::Output.new(**args)
      end

      private

      def load_perform_code
        instance_eval("def perform(row)\n#{code}\nend", __FILE__, __LINE__)
      end

      def run_before_code
        instance_eval(before_code) if before_code
      end

      def run_after_code
        instance_eval(after_code) if after_code
      end

      def validate_code
        return if code.nil?

        validate_field(:code) { load_perform_code }
      end

      def validate_before_code
        return if before_code.nil?

        validate_field(:before_code) { instance_eval("def __before_code\n#{before_code}\nend", __FILE__, __LINE__) }
      end

      def validate_after_code
        return if after_code.nil?

        validate_field(:after_code) { instance_eval("def __after_code\n#{after_code}\nend", __FILE__, __LINE__) }
      end

      def validate_field(field)
        yield
      rescue Exception => e
        errors.add(field, "Failed to load :#{field}, #{e.inspect}")
      end

      # Allow multiple instances of this job to run with the same cron schedule
      def rocket_job_cron_singleton_check
      end
    end
  end
end

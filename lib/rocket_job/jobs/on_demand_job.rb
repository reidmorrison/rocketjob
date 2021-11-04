# Job to dynamically perform ruby code on demand,
#
# Create or schedule a generalized job for one off fixes or cleanups.
#
# Example: Iterate over all rows in a table:
#   code = <<~CODE
#     User.unscoped.all.order('updated_at DESC').each |user|
#       user.cleanse_attributes!
#       user.save!
#     end
#   CODE
#
#   RocketJob::Jobs::OnDemandJob.create!(
#     code:          code,
#     description:   'Cleanse users'
#   )
#
# Example: Test job in a console:
#   code = <<~CODE
#     User.unscoped.all.order('updated_at DESC').each |user|
#       user.cleanse_attributes!
#       user.save!
#     end
#   CODE
#
#   job = RocketJob::Jobs::OnDemandJob.new(code: code, description: 'cleanse users')
#   job.perform_now
#
# Example: Pass input data:
#   code = <<~CODE
#     puts data['a'] * data['b']
#   CODE
#
#   RocketJob::Jobs::OnDemandJob.create!(
#     code: code,
#     data: {'a' => 10, 'b' => 2}
#   )
#
# Example: Retain output:
#   code = <<~CODE
#     data['result'] = data['a'] * data['b']
#   CODE
#
#   RocketJob::Jobs::OnDemandJob.create!(
#     code:           code,
#     data:           {'a' => 10, 'b' => 2}
#   )
#
# Example: Schedule the job to run nightly at 2am Eastern:
#
#   RocketJob::Jobs::OnDemandJob.create!(
#     cron_schedule: '0 2 * * * America/New_York',
#     code:          code
#   )
#
# Example: Change the job priority, description, etc.
#
#   RocketJob::Jobs::OnDemandJob.create!(
#     code:          code,
#     description:   'Cleanse users',
#     priority:      30
#   )
#
# Example: Automatically retry up to 5 times on failure:
#
#   RocketJob::Jobs::OnDemandJob.create!(
#     retry_limit: 5
#     code:        code
#   )
module RocketJob
  module Jobs
    class OnDemandJob < RocketJob::Job
      include RocketJob::Plugins::Cron
      include RocketJob::Plugins::Retry

      self.description         = "On Demand Job"
      self.destroy_on_complete = false
      self.retry_limit         = 0

      # Be sure to store key names only as Strings, not Symbols
      field :data, type: Hash, default: {}, user_editable: true, copy_on_restart: true
      field :code, type: String, user_editable: true, copy_on_restart: true

      validates :code, presence: true
      validate :validate_code

      before_perform :load_code

      private

      def load_code
        instance_eval("def perform\n#{code}\nend", __FILE__, __LINE__)
      end

      def validate_code
        load_code
      rescue Exception => e
        errors.add(:code, "Failed to parse :code, #{e.inspect}")
      end

      # Allow multiple instances of this job to run with the same cron schedule
      def rocket_job_cron_singleton_check
      end
    end
  end
end

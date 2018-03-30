# Generalized Job.
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
#   RocketJob::Jobs::GeneralizedJob.create!(
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
#   job = RocketJob::Jobs::GeneralizedJob.new(code: code, description: 'cleanse users')
#   job.perform_now
#
# Example: Pass input data:
#   code = <<~CODE
#     puts data['a'] * data['b']
#   CODE
#
#   RocketJob::Jobs::GeneralizedJob.create!(
#     code: code,
#     data: {'a' => 10, 'b' => 2}
#   )
#
# Example: Retain output:
#   code = <<~CODE
#     {'value' => data['a'] * data['b']}
#   CODE
#
#   RocketJob::Jobs::GeneralizedJob.create!(
#     code:           code,
#     collect_output: true,
#     data:           {'a' => 10, 'b' => 2}
#   )
#
# Example: Schedule the job to run nightly at 2am Eastern:
#
#   RocketJob::Jobs::GeneralizedJob.create!(
#     cron_schedule: '0 2 * * * America/New_York',
#     code:          code
#   )
#
# Example: Change the job priority, description, etc.
#
#   RocketJob::Jobs::GeneralizedJob.create!(
#     code:          code,
#     description:   'Cleanse users',
#     priority:      30
#   )
#
# Example: Automatically retry up to 5 times on failure:
#
#   RocketJob::Jobs::GeneralizedJob.create!(
#     retry_limit: 5
#     code:        code
#   )
module RocketJob
  module Jobs
    class GeneralizedJob < RocketJob::Job
      include RocketJob::Plugins::Cron
      include RocketJob::Plugins::Retry

      self.priority            = 90
      self.description         = 'Generalized Job'
      self.destroy_on_complete = false
      self.retry_limit         = 0

      # Be sure to store key names only as Strings, not Symbols
      field :data, type: Hash, default: {}
      field :code, type: String

      validates :code, presence: true
      validates_each :code do |job, attr, value|
        begin
          job.send(:load_code)
        rescue Exception => exc
          job.errors.add(attr, "Failed to parse :code, #{exc.inspect}")
        end
      end

      before_perform :load_code

      private

      def load_code
        instance_eval("def perform\n#{code}\nend")
      end
    end
  end
end

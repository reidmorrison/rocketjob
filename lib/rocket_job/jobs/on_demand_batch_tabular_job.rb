# Job to dynamically perform ruby code on demand as a Batch,
# with input and/or output from CSV/JSON or other format supported by Tabular.
#
# Nodes:
# - Need to specify `destroy_on_complete: false` to collect output from this job.
# - `after_code` can be used to automatically download the output of this job to a file on completion.
#
# Example: Iterate over all rows in a table:
#   code = <<-CODE
#     if user = User.find(row)
#       user.cleanse_attributes!
#       user.save(validate: false)
#     end
#   CODE
#   job  = RocketJob::Jobs::OnDemandBatchTabularJob.new(code: code, description: 'cleanse users', destroy_on_complete: false)
#   job.upload("users.csv")
#   job.save!
#
# On completion export the output:
# job.download("output.csv")
module RocketJob
  module Jobs
    class OnDemandBatchTabularJob < OnDemandBatchJob
      include RocketJob::Batch::Tabular
    end
  end
end

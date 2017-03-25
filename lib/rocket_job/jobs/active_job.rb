module RocketJob
  module Jobs
    # Used to wrap an Active Job
    class ActiveJob < RocketJob::Job #:nodoc:
      field :data, type: Hash
      field :active_job_id, type: String
      field :active_job_class, type: String
      field :active_job_queue, type: String

      def perform
        ::ActiveJob::Base.execute data
      end
    end
  end
end

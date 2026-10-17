require_relative "../test_helper"
require "active_job"
require "rocket_job/extensions/rocket_job_adapter"

module Extensions
  class RocketJobAdapterTest < Minitest::Test
    class AdapterTestJob < ActiveJob::Base
      self.queue_adapter = :rocket_job

      def perform(value)
        value
      end
    end

    class PriorityTestJob < AdapterTestJob
      queue_with_priority 20
    end

    describe ActiveJob::QueueAdapters::RocketJobAdapter do
      before do
        ActiveJob::Base.logger = ActiveSupport::TaggedLogging.new(::Logger.new(IO::NULL))
        RocketJob::Jobs::ActiveJob.delete_all
      end

      after do
        RocketJob::Jobs::ActiveJob.delete_all
      end

      it "is the adapter that Active Job creates for :rocket_job" do
        assert_kind_of ActiveJob::QueueAdapters::RocketJobAdapter, AdapterTestJob.queue_adapter
      end

      describe "#enqueue" do
        it "queues a Rocket Job for perform_later" do
          active_job = AdapterTestJob.perform_later("hello")
          job        = RocketJob::Jobs::ActiveJob.find(active_job.provider_job_id)

          assert_predicate job, :queued?
          assert_nil job.run_at
          assert_equal AdapterTestJob.name, job.active_job_class
          assert_equal active_job.job_id, job.active_job_id
          assert_equal "default", job.active_job_queue
          assert_equal AdapterTestJob.name, job.description
        end

        it "keeps the priority of the Active Job" do
          active_job = PriorityTestJob.perform_later("hello")

          assert_equal 20, RocketJob::Jobs::ActiveJob.find(active_job.provider_job_id).priority
        end

        it "performs the Active Job when the Rocket Job runs" do
          active_job = AdapterTestJob.perform_later("hello")
          job        = RocketJob::Jobs::ActiveJob.find(active_job.provider_job_id)

          assert_equal "hello", job.perform
        end
      end

      describe "#enqueue_at" do
        it "schedules a Rocket Job for set(wait:)" do
          active_job = AdapterTestJob.set(wait: 5.minutes).perform_later("hello")
          job        = RocketJob::Jobs::ActiveJob.find(active_job.provider_job_id)

          assert_predicate job, :scheduled?
          assert_in_delta 5.minutes.from_now.to_f, job.run_at.to_f, 5
        end
      end

      describe ".enqueue" do
        it "queues a Rocket Job when called on the class" do
          job = ActiveJob::QueueAdapters::RocketJobAdapter.enqueue(AdapterTestJob.new("hello"))

          assert_predicate job, :persisted?
          assert_equal AdapterTestJob.name, job.active_job_class
        end
      end
    end
  end
end

require_relative "../test_helper"

module Batch
  class ThrottleTest < Minitest::Test
    class ThrottleJob < RocketJob::Job
      include RocketJob::Batch

      # Only allow one to be processed at a time
      self.throttle_running_jobs    = 1
      self.throttle_running_workers = 1
      self.slice_size               = 1

      def perform(record)
        record
      end
    end

    describe RocketJob::Batch::Throttle do
      before do
        skip("Throttle tests fail intermittently on Travis CI") if ENV["TRAVIS"]
        RocketJob::Job.destroy_all
      end

      after do
        RocketJob::Job.destroy_all
      end

      let(:job) do
        job = ThrottleJob.new
        job.upload do |stream|
          stream << "first"
          stream << "second"
        end
        job.save!
        assert_equal 2, job.input.count
        job
      end

      let(:worker) { RocketJob::Worker.new(inline: true) }

      describe ".batch_throttle?" do
        it "defines the running slices throttle" do
          assert ThrottleJob.batch_throttle?(:throttle_running_workers_exceeded?), ThrottleJob.rocket_job_batch_throttles
          refute ThrottleJob.batch_throttle?(:blah?), ThrottleJob.rocket_job_batch_throttles
        end
      end

      describe ".undefine_batch_throttle" do
        it "undefines the running jobs throttle" do
          assert ThrottleJob.batch_throttle?(:throttle_running_workers_exceeded?), ThrottleJob.rocket_job_batch_throttles
          ThrottleJob.undefine_batch_throttle(:throttle_running_workers_exceeded?)
          refute ThrottleJob.batch_throttle?(:throttle_running_workers_exceeded?), ThrottleJob.rocket_job_batch_throttles
          ThrottleJob.define_batch_throttle(:throttle_running_workers_exceeded?)
          assert ThrottleJob.batch_throttle?(:throttle_running_workers_exceeded?), ThrottleJob.rocket_job_batch_throttles
        end
      end

      describe "#throttle_running_workers_exceeded?" do
        it "does not exceed throttle when no other slices are running" do
          slice = job.input.first
          refute job.send(:throttle_running_workers_exceeded?, slice)
        end

        it "exceeds throttle when other slices are running" do
          job.input.first.start!
          slice = job.input.last
          assert job.send(:throttle_running_workers_exceeded?, slice)
        end

        it "does not exceed throttle when other slices are failed" do
          job.input.first.fail!
          slice = job.input.last
          refute job.send(:throttle_running_workers_exceeded?, slice)
        end
      end

      describe "#throttle_running_jobs_exceeded?" do
        it "does not exceed throttle when no jobs are running" do
          job = ThrottleJob.create!
          refute job.send(:throttle_running_jobs_exceeded?)
        end

        it "does not exceed throttle when no other jobs are running" do
          job = ThrottleJob.new
          job.start!
          refute job.send(:throttle_running_jobs_exceeded?)
        end

        it "exceeds throttle when other jobs are running with same priority" do
          job1 = ThrottleJob.new
          job1.start!
          job = ThrottleJob.create!
          assert job.send(:throttle_running_jobs_exceeded?)
        end

        it "exceeds throttle when job has a lower priority" do
          job1 = ThrottleJob.new
          job1.start!
          job = ThrottleJob.create!(priority: 51)
          assert job.send(:throttle_running_jobs_exceeded?)
        end

        it "does not exceed throttle when job has a higher priority" do
          job1 = ThrottleJob.new
          job1.start!
          job = ThrottleJob.create!(priority: 49)
          refute job.send(:throttle_running_jobs_exceeded?)
        end

        it "does not exceed throttle when other slices are failed" do
          job1 = ThrottleJob.new
          job1.start
          job1.fail!
          job = ThrottleJob.create!
          refute job.send(:throttle_running_jobs_exceeded?)
        end

        it "does not exceed throttle when other slices are paused" do
          job1 = ThrottleJob.create!(state: :paused)
          job = ThrottleJob.create!
          refute job.send(:throttle_running_jobs_exceeded?)
        end
      end

      describe "#rocket_job_work" do
        before do
          job.start!
        end

        it "process all slices when all are queued" do
          # skip "TODO: Intermittent test failure"
          refute job.rocket_job_work(worker, true)
          assert job.completed?, -> { job.ai }
        end

        it "return true when other slices are running" do
          job.input.first.start!
          assert job.rocket_job_work(worker, true)
          assert job.running?
          assert_equal 2, job.input.count
        end

        it "process non failed slices" do
          # skip "TODO: Intermittent test failure"
          job.input.first.fail!
          refute job.rocket_job_work(worker, true)
          assert job.failed?
          assert_equal 1, job.input.count
        end

        it "update filter when other slices are running" do
          # skip "TODO: Intermittent test failure"
          job.input.first.start!
          assert job.rocket_job_work(worker, true)
          assert job.running?
          assert_equal 2, job.input.count
          either_filter = [{:id.nin => [job.id]}, {:_type.nin => [job.class.name]}]
          assert(either_filter.include?(worker.current_filter), -> { ThrottleJob.all.to_a.ai })
        end

        it "returns slice when other slices are running for later processing" do
          job.input.first.start!
          assert job.rocket_job_work(worker, true)
          assert job.running?
          assert_equal 1, job.input.running.count
          assert_equal 1, job.input.queued.count

          job.input.first.destroy
          assert_equal 1, job.input.count
          assert_equal 1, job.input.queued.count
          refute job.rocket_job_work(worker, true)
          assert_equal 0, job.input.count, -> { job.input.first.attributes.ai }
          assert job.completed?, -> { job.ai }
        end
      end
    end
  end
end

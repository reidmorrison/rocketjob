require_relative "../../test_helper"

module Plugins
  module Job
    class ThrottleTest < Minitest::Test
      class ThrottleJob < RocketJob::Job
        # Only allow one to be processed at a time
        self.throttle_running_jobs = 1
        self.pausable              = true

        def perform
          21
        end
      end

      class ThrottleGroupJob < RocketJob::Job
        # Only allow one to be processed at a time
        self.throttle_running_jobs = 1
        self.throttle_group        = "writer-group"
        self.pausable              = true

        def perform
          21
        end
      end

      class ThrottleGroupOtherJob < RocketJob::Job
        # Only allow one to be processed at a time
        self.throttle_running_jobs = 1
        self.throttle_group        = "writer-group"
        self.pausable              = true

        def perform
          21
        end
      end

      class BaseJob < RocketJob::Job
        define_throttle :base_throttle

        private

        def base_throttle
          false
        end
      end

      class ChildJob < BaseJob
        define_throttle :child_throttle

        private

        def child_throttle
          false
        end
      end

      class RunningJobsDescriptionJob < RocketJob::Job
        self.throttle_running_jobs = 7

        def perform
          21
        end
      end

      class DescribedThrottleJob < RocketJob::Job
        define_throttle :static_throttle, description: "Custom static reason"
        define_throttle :proc_throttle, description: ->(job, *) { "Reason for #{job.class.name}" }
        define_throttle :default_throttle_exceeded?

        private

        def static_throttle
          false
        end

        def proc_throttle
          false
        end

        def default_throttle_exceeded?
          false
        end
      end

      describe RocketJob::Plugins::Job::Throttle do
        before do
          RocketJob::Job.delete_all
        end

        after do
          RocketJob::Job.delete_all
        end

        describe ".throttle?" do
          it "defines the running jobs throttle" do
            assert ThrottleJob.throttle?(:throttle_running_jobs_exceeded?), ThrottleJob.rocket_job_throttles
            refute ThrottleJob.throttle?(:blah?), ThrottleJob.rocket_job_throttles
          end
        end

        describe ".define_throttle" do
          it "creates base throttle" do
            assert BaseJob.throttle?(:base_throttle)
            refute BaseJob.throttle?(:child_throttle)
          end

          it "inherits parent throttles" do
            assert ChildJob.throttle?(:base_throttle)
            assert ChildJob.throttle?(:child_throttle)
          end
        end

        describe ".undefine_throttle" do
          it "undefines the running jobs throttle" do
            assert ThrottleJob.throttle?(:throttle_running_jobs_exceeded?), ThrottleJob.rocket_job_throttles.throttles
            ThrottleJob.undefine_throttle(:throttle_running_jobs_exceeded?)

            refute ThrottleJob.throttle?(:throttle_running_jobs_exceeded?), ThrottleJob.rocket_job_throttles.throttles
            ThrottleJob.define_throttle(:throttle_running_jobs_exceeded?)

            assert ThrottleJob.throttle?(:throttle_running_jobs_exceeded?), ThrottleJob.rocket_job_throttles.throttles
          end
        end

        describe "throttle descriptions" do
          let(:throttles) { DescribedThrottleJob.rocket_job_throttles }

          it "uses a static description string" do
            throttle = throttles.throttles.find { |t| t.method_name == :static_throttle }

            assert_equal "Custom static reason", throttle.extract_description(DescribedThrottleJob.new)
          end

          it "evaluates a Proc description" do
            throttle = throttles.throttles.find { |t| t.method_name == :proc_throttle }

            assert_equal "Reason for #{DescribedThrottleJob.name}", throttle.extract_description(DescribedThrottleJob.new)
          end

          it "humanizes the method name when no description is given" do
            throttle = throttles.throttles.find { |t| t.method_name == :default_throttle_exceeded? }

            assert_equal "Default throttle", throttle.extract_description(DescribedThrottleJob.new)
          end

          it "describes the running jobs throttle with the limit" do
            throttle = RunningJobsDescriptionJob.rocket_job_throttles.throttles.find { |t| t.method_name == :throttle_running_jobs_exceeded? }

            assert_equal "Throttled: maximum of 7 running jobs reached", throttle.extract_description(RunningJobsDescriptionJob.new)
          end
        end

        describe "#matching_throttle" do
          it "returns the triggered throttle" do
            job1 = ThrottleJob.new
            job1.start!
            job2 = ThrottleJob.new

            throttle = job2.rocket_job_throttles.matching_throttle(job2)

            assert throttle
            assert_equal :throttle_running_jobs_exceeded?, throttle.method_name
          end

          it "returns nil when no throttle is triggered" do
            job = ThrottleJob.new

            assert_nil job.rocket_job_throttles.matching_throttle(job)
          end
        end

        describe "#throttle_running_jobs_exceeded?" do
          it "does not exceed throttle when no other jobs are running" do
            ThrottleJob.create!
            job = ThrottleJob.new

            refute job.send(:throttle_running_jobs_exceeded?)
          end

          it "exceeds throttle when other jobs are running" do
            job1 = ThrottleJob.new
            job1.start!
            job2 = ThrottleJob.new

            assert job2.send(:throttle_running_jobs_exceeded?)
          end

          it "excludes paused jobs" do
            job1 = ThrottleJob.new
            job1.start
            job1.pause!
            job2 = ThrottleJob.new

            refute job2.send(:throttle_running_jobs_exceeded?)
          end

          it "excludes failed jobs" do
            job1 = ThrottleJob.new
            job1.start
            job1.fail!
            job2 = ThrottleJob.new

            refute job2.send(:throttle_running_jobs_exceeded?)
          end

          it "by default it has no group name" do
            assert_nil ThrottleJob.throttle_group
          end
        end

        describe "#throttle_running_jobs_exceeded? for a named group" do
          it "sets the group name" do
            assert_equal "writer-group", ThrottleGroupJob.throttle_group
            assert_equal "writer-group", ThrottleGroupOtherJob.throttle_group
          end

          it "does not exceed throttle when no other jobs are running" do
            ThrottleGroupJob.create!
            ThrottleGroupOtherJob.create!
            job = ThrottleGroupJob.new

            refute job.send(:throttle_running_jobs_exceeded?)
          end

          it "exceeds throttle when other jobs are running" do
            job1 = ThrottleGroupJob.new
            job1.start!
            job2 = ThrottleGroupJob.new

            assert job2.send(:throttle_running_jobs_exceeded?)
          end

          it "exceeds throttle when other group jobs are running" do
            job1 = ThrottleGroupOtherJob.new
            job1.start!
            job2 = ThrottleGroupJob.new

            assert job2.send(:throttle_running_jobs_exceeded?)
          end

          it "excludes paused jobs" do
            job1 = ThrottleGroupOtherJob.new
            job1.start
            job1.pause!
            job2 = ThrottleGroupJob.new

            refute job2.send(:throttle_running_jobs_exceeded?)
          end

          it "excludes failed jobs" do
            job1 = ThrottleGroupOtherJob.new
            job1.start
            job1.fail!
            job2 = ThrottleGroupJob.new

            refute job2.send(:throttle_running_jobs_exceeded?)
          end
        end
      end
    end
  end
end

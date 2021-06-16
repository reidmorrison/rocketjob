require_relative "../../test_helper"
module Plugins
  module Job
    class ThrottleDependentJobsTest < Minitest::Test
      class RegularTestJob < RocketJob::Job
        include RocketJob::Plugins::ThrottleDependentJobs
        self.dependent_jobs = ["Plugins::Job::ThrottleDependentJobsTest::DependentTestJob"].freeze
      end

      class DependentTestJob < RocketJob::Job
      end

      describe RocketJob::Plugins::ThrottleDependentJobs do
        before do
          RocketJob::Job.delete_all
        end

        after do
          RocketJob::Job.delete_all
        end

        let(:job) do
          RegularTestJob.new
        end

        describe "with a regular job" do
          it "defines the dependent job throttle" do
            assert RegularTestJob.throttle?(:dependent_job_exists?), RegularTestJob.rocket_job_throttles
          end

          it "exceeds the throttle if there is any dependent job running" do
            dependent_job = DependentTestJob.new
            dependent_job.start!
            assert job.send(:dependent_job_exists?)
          end

          it "does not exceed the throttle when there are no dependent jobs" do
            refute job.send(:dependent_job_exists?)
          end
        end
      end
    end
  end
end

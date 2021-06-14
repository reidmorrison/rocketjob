require_relative "../../test_helper"
module Plugins
  module Job
    class ThrottleDependantJobsTest < Minitest::Test
      class RegularTestJob < RocketJob::Job
        self.dependant_jobs = ["Plugins::Job::ThrottleDependantJobsTest::DependantTestJob"].freeze
      end

      class DependantTestJob < RocketJob::Job
      end

      describe RocketJob::Plugins::Job::ThrottleDependantJobs do
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
          it "defines the dependant job throttle" do
            assert RegularTestJob.throttle?(:dependant_job_exists?), RegularTestJob.rocket_job_throttles
          end

          it "exceeds the throttle if there is any dependant job running" do
            dependant_job = DependantTestJob.new
            dependant_job.start!
            assert job.send(:dependant_job_exists?)
          end

          it "does not exceed the throttle when there are no dependant jobs" do
            refute job.send(:dependant_job_exists?)
          end
        end
      end
    end
  end
end

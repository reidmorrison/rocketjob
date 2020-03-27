require_relative '../../test_helper'

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

      describe RocketJob::Plugins::Job::Throttle do
        before do
          RocketJob::Job.delete_all
        end

        after do
          RocketJob::Job.delete_all
        end

        describe '.throttle?' do
          it 'defines the running jobs throttle' do
            assert ThrottleJob.throttle?(:throttle_running_jobs_exceeded?), ThrottleJob.rocket_job_throttles
            refute ThrottleJob.throttle?(:blah?), ThrottleJob.rocket_job_throttles
          end
        end

        describe '.undefine_throttle' do
          it 'undefines the running jobs throttle' do
            assert ThrottleJob.throttle?(:throttle_running_jobs_exceeded?), ThrottleJob.rocket_job_throttles
            ThrottleJob.undefine_throttle(:throttle_running_jobs_exceeded?)
            refute ThrottleJob.throttle?(:throttle_running_jobs_exceeded?), ThrottleJob.rocket_job_throttles
            ThrottleJob.define_throttle(:throttle_running_jobs_exceeded?)
            assert ThrottleJob.throttle?(:throttle_running_jobs_exceeded?), ThrottleJob.rocket_job_throttles
          end
        end

        describe '#throttle_running_jobs_exceeded??' do
          it 'does not exceed throttle when no other jobs are running' do
            ThrottleJob.create!
            job = ThrottleJob.new
            refute job.send(:throttle_running_jobs_exceeded?)
          end

          it 'exceeds throttle when other jobs are running' do
            job1 = ThrottleJob.new
            job1.start!
            job2 = ThrottleJob.new
            assert job2.send(:throttle_running_jobs_exceeded?)
          end

          it 'excludes paused jobs' do
            job1 = ThrottleJob.new
            job1.start
            job1.pause!
            job2 = ThrottleJob.new
            refute job2.send(:throttle_running_jobs_exceeded?)
          end

          it 'excludes failed jobs' do
            job1 = ThrottleJob.new
            job1.start
            job1.fail!
            job2 = ThrottleJob.new
            refute job2.send(:throttle_running_jobs_exceeded?)
          end
        end
      end
    end
  end
end

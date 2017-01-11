require_relative '../../test_helper'

# Unit Test for RocketJob::Job
module Plugins
  module Job
    class ThrottleTest < Minitest::Test

      class ThrottleJob < RocketJob::Job
        # Only allow one to be processed at a time
        self.throttle_max_workers = 1

        def perform
          21
        end
      end

      describe RocketJob::Plugins::Job::Logger do
        before do
          ThrottleJob.delete_all
        end

        describe '#throttle_exceeded?' do
          it 'does not exceed throttle when no other jobs are running' do
            ThrottleJob.create!
            job = ThrottleJob.new
            refute job.throttle_exceeded?
          end

          it 'exceeds throttle when other jobs are running' do
            job1 = ThrottleJob.new
            job1.start!
            job2 = ThrottleJob.new
            assert job2.throttle_exceeded?
          end

          it 'excludes paused jobs' do
            job1 = ThrottleJob.new
            job1.start
            job1.pause!
            job2 = ThrottleJob.new
            refute job2.throttle_exceeded?
          end

          it 'excludes failed jobs' do
            job1 = ThrottleJob.new
            job1.start
            job1.fail!
            job2 = ThrottleJob.new
            refute job2.throttle_exceeded?
          end
        end

      end
    end
  end
end

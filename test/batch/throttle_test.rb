require_relative '../test_helper'

module Batch
  class ThrottleTest < Minitest::Test
    class ThrottleJob < RocketJob::Job
      include RocketJob::Batch

      # Only allow one to be processed at a time
      self.throttle_running_jobs   = 1
      self.throttle_running_slices = 1
      self.slice_size              = 1

      def perform(record)
        record
      end
    end

    describe RocketJob::Batch::Throttle do
      before do
        skip("Throttle tests fail intermittently on Travis CI") if ENV["TRAVIS"]
        RocketJob::Job.delete_all

        @job = ThrottleJob.new
        @job.upload do |stream|
          stream << 'first'
          stream << 'second'
        end
        @job.save!
        assert_equal 2, @job.input.count
      end

      after do
        @job.destroy if @job && !@job.new_record?
      end

      describe '.batch_throttle?' do
        it 'defines the running slices throttle' do
          assert ThrottleJob.batch_throttle?(:throttle_running_slices_exceeded?), ThrottleJob.rocket_job_batch_throttles
          refute ThrottleJob.batch_throttle?(:blah?), ThrottleJob.rocket_job_batch_throttles
        end
      end

      describe '.undefine_batch_throttle' do
        it 'undefines the running jobs throttle' do
          assert ThrottleJob.batch_throttle?(:throttle_running_slices_exceeded?), ThrottleJob.rocket_job_batch_throttles
          ThrottleJob.undefine_batch_throttle(:throttle_running_slices_exceeded?)
          refute ThrottleJob.batch_throttle?(:throttle_running_slices_exceeded?), ThrottleJob.rocket_job_batch_throttles
          ThrottleJob.define_batch_throttle(:throttle_running_slices_exceeded?)
          assert ThrottleJob.batch_throttle?(:throttle_running_slices_exceeded?), ThrottleJob.rocket_job_batch_throttles
        end
      end

      describe '#throttle_running_slices_exceeded?' do
        it 'does not exceed throttle when no other slices are running' do
          slice = @job.input.first
          refute @job.send(:throttle_running_slices_exceeded?, slice)
        end

        it 'exceeds throttle when other slices are running' do
          @job.input.first.start!
          slice = @job.input.last
          assert @job.send(:throttle_running_slices_exceeded?, slice)
        end

        it 'does not exceed throttle when other slices are failed' do
          @job.input.first.fail!
          slice = @job.input.last
          refute @job.send(:throttle_running_slices_exceeded?, slice)
        end
      end

      describe '.rocket_job_work' do
        before do
          @worker = RocketJob::Worker.new
          @job.start!
        end

        it 'process all slices when all are queued' do
          skip "TODO: Intermittent test failure"
          refute @job.rocket_job_work(@worker, true)
          assert @job.completed?, -> { @job.ai }
        end

        it 'return true when other slices are running' do
          @job.input.first.start!
          assert @job.rocket_job_work(@worker, true)
          assert @job.reload.running?
          assert_equal 2, @job.input.count
        end

        it 'process non failed slices' do
          skip "TODO: Intermittent test failure"
          @job.input.first.fail!
          refute @job.rocket_job_work(@worker, true)
          assert @job.reload.failed?
          assert_equal 1, @job.input.count
        end

        it 'update filter when other slices are running' do
          skip "TODO: Intermittent test failure"
          @job.input.first.start!
          filter = {}
          assert @job.rocket_job_work(@worker, true, filter)
          assert @job.reload.running?
          assert_equal 2, @job.input.count
          assert_equal 1, filter.size
        end

        it 'returns slice when other slices are running for later processing' do
          @job.input.first.start!
          assert @job.rocket_job_work(@worker, true)
          assert @job.reload.running?
          assert_equal 1, @job.input.running.count
          assert_equal 1, @job.input.queued.count

          @job.input.first.destroy
          assert_equal 1, @job.input.count
          assert_equal 1, @job.input.queued.count
          refute @job.rocket_job_work(@worker, true)
          assert_equal 0, @job.input.count, -> { @job.input.first.attributes.ai }
          assert @job.reload.completed?, -> { @job.ai }
        end
      end
    end
  end
end

require_relative 'test_helper'
require_relative 'workers/job'
require_relative 'workers/batch_job'

# Unit Test for RocketJob::Job
class WorkerTest < Minitest::Test
  context RocketJob::Worker do
    [true, false].each do |test_mode|
      setup do
        RocketJob::Config.test_mode = test_mode
        @server = RocketJob::Server.new
      end

      teardown do
        @job.destroy if @job && !@job.new_record?
        RocketJob::Config.test_mode = false
      end

      context '#perform_later' do
        should "process single request (test_mode=#{test_mode})" do
          @job = Workers::Job.perform_later(1)
          assert_nil   @job.server
          assert_nil   @job.completed_at
          assert       @job.created_at
          assert_nil   @job.description
          skip 'need ability to set destroy_on_complete to false'
          assert_equal false, @job.destroy_on_complete
          assert_nil   @job.expires_at
          assert_nil   @job.group
          assert_equal 0, @job.percent_complete
          assert_equal 50, @job.priority
          assert_equal true, @job.repeatable
          assert_equal 0, @job.failure_count
          assert_nil   @job.run_at
          assert_nil   @job.schedule
          assert_nil   @job.started_at
          assert_equal :queued, @job.state

          @job.server = 'me'
          @job.start
          assert_equal 1, @job.work(@server), @job.exception.inspect
          assert_equal true, @job.completed?
          assert_equal 2,    Workers::Job.result

          assert       @job.server
          assert       @job.completed_at
          assert       @job.created_at
          assert_nil   @job.description
          assert_equal false, @job.destroy_on_complete
          assert_nil   @job.expires_at
          assert_nil   @job.group
          assert_equal 100, @job.percent_complete
          assert_equal 50, @job.priority
          assert_equal true, @job.repeatable
          assert_equal 0, @job.failure_count
          assert_nil   @job.run_at
          assert_nil   @job.schedule
          assert       @job.started_at
        end

        should "process multi-record request (test_mode=#{test_mode})" do
          @lines = [ 'line1', 'line2', 'line3', 'line4', 'line5' ]
          @job = Workers::BatchJob.perform_later do |job|
            job.collect_output = true
            job.input_slice @lines
            job.destroy_on_complete = false
          end
          assert_equal RocketJob::BatchJob, @job.class
          assert_equal @lines.size, @job.record_count
          assert_nil   @job.server
          assert_nil   @job.completed_at
          assert       @job.created_at
          assert_nil   @job.description
          assert_equal false, @job.destroy_on_complete
          assert_nil   @job.expires_at
          assert_nil   @job.group
          assert_equal 0, @job.percent_complete
          assert_equal 50, @job.priority
          assert_equal true, @job.repeatable
          assert_equal 0, @job.failure_count
          assert_nil   @job.run_at
          assert_nil   @job.schedule
          assert_nil   @job.started_at
          assert_equal :queued, @job.state

          @job.start!
          @job.save!
          assert_equal 5, @job.work(@server), @job.exception.inspect
          assert_equal 0, @job.slices_failed
          assert_equal @lines.size, @job.record_count
          assert_equal 0, @job.slices_queued
          assert_equal true, @job.completed?
          @job.each_output_slice do |slice|
            assert_equal @lines, slice
          end

          assert       @job.completed_at
          assert       @job.created_at
          assert_nil   @job.description
          assert_equal false, @job.destroy_on_complete
          assert_nil   @job.expires_at
          assert_nil   @job.group
          assert_equal 100, @job.percent_complete
          assert_equal 50, @job.priority
          assert_equal true, @job.repeatable
          assert_equal 0, @job.failure_count
          assert_nil   @job.run_at
          assert_nil   @job.schedule
          assert       @job.started_at
        end
      end

      context '#later' do
        should "process non default method (test_mode=#{test_mode})" do
          @job = Workers::Job.later(:sum, 23, 45)
          @job.start
          assert_equal 1, @job.work(@server), @job.exception.inspect
          assert_equal true, @job.completed?
          assert_equal 68,    Workers::Job.result
        end
      end

    end
  end
end
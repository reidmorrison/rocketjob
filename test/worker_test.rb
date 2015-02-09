require_relative 'test_helper'
require_relative 'workers/single'

# Unit Test for BatchJob::Single
class WorkerTest < Minitest::Test
  context BatchJob::Worker do
    [true, false].each do |test_mode|
      setup do
        BatchJob::Config.test_mode = test_mode
      end

      teardown do
        @job.destroy if @job && !@job.new_record?
        BatchJob::Config.test_mode = false
      end

      context '#async_perform' do
        should "process single request (test_mode=#{test_mode})" do
          @job = Workers::Single.async_perform(1)
          assert_nil   @job.server
          assert_nil   @job.completed_at
          assert       @job.created_at
          assert_nil   @job.description
          assert_equal false, @job.destroy_on_completion
          assert_equal 0, @job.email_addresses.count
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

          assert_equal true, @job.work
          assert_equal true, @job.completed?
          assert_equal 2,    Workers::Single.result

          assert       @job.server
          assert       @job.completed_at
          assert       @job.created_at
          assert_nil   @job.description
          assert_equal false, @job.destroy_on_completion
          assert_equal 0, @job.email_addresses.count
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
          @job = Workers::MultiRecord.async_perform(1)
          assert_nil   @job.server
          assert_nil   @job.completed_at
          assert       @job.created_at
          assert_nil   @job.description
          assert_equal false, @job.destroy_on_completion
          assert_equal 0, @job.email_addresses.count
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

          assert_equal true, @job.work
          assert_equal true, @job.completed?
          assert_equal 2,    Workers::Single.result

          assert       @job.server
          assert       @job.completed_at
          assert       @job.created_at
          assert_nil   @job.description
          assert_equal false, @job.destroy_on_completion
          assert_equal 0, @job.email_addresses.count
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

      context '#async' do
        should "process non default method (test_mode=#{test_mode})" do
          @job = Workers::Single.async(:sum, 23, 45)
          assert_equal true, @job.work
          assert_equal true, @job.completed?
          assert_equal 68,    Workers::Single.result
        end
      end

    end
  end
end
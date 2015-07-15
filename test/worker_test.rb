require_relative 'test_helper'
require_relative 'jobs/test_job'

# Unit Test for RocketJob::Job
class WorkerTest < Minitest::Test
  context RocketJob::Job do
    [true, false].each do |inline_mode|
      setup do
        RocketJob::Config.inline_mode = inline_mode
        @server = RocketJob::Server.new
        @server.started
      end

      teardown do
        @job.destroy if @job && !@job.new_record?
        RocketJob::Config.inline_mode = false
      end

      context '.perform_later' do
        should "process single request (inline_mode=#{inline_mode})" do
          @job = Jobs::TestJob.perform_later(1) do |job|
            job.destroy_on_complete = false
          end
          assert_nil   @job.server_name
          assert_nil   @job.completed_at
          assert       @job.created_at
          assert_nil   @job.description
          assert_equal false, @job.destroy_on_complete
          assert_nil   @job.expires_at
          assert_equal 0, @job.percent_complete
          assert_equal 50, @job.priority
          assert_equal 0, @job.failure_count
          assert_nil   @job.run_at
          assert_nil   @job.started_at
          assert_equal :queued, @job.state

          @job.server_name = 'me'
          @job.start
          assert_equal false,    @job.work(@server), @job.exception.inspect
          assert_equal true, @job.completed?
          assert_equal 2,    Jobs::TestJob.result

          assert       @job.server_name
          assert       @job.completed_at
          assert       @job.created_at
          assert_nil   @job.description
          assert_equal false, @job.destroy_on_complete
          assert_nil   @job.expires_at
          assert_equal 100, @job.percent_complete
          assert_equal 50, @job.priority
          assert_equal 0, @job.failure_count
          assert_nil   @job.run_at
          assert       @job.started_at
        end
      end

      context '.later' do
        should "process non default method (inline_mode=#{inline_mode})" do
          @job = Jobs::TestJob.later(:sum, 23, 45)
          @job.start
          assert_equal false, @job.work(@server), @job.exception.inspect
          assert_equal true,  @job.completed?
          assert_equal 68,    Jobs::TestJob.result
        end
      end

      context '.perform_now' do
        should "process perform (inline_mode=#{inline_mode})" do
          @job = Jobs::TestJob.perform_now(5)
          assert_equal true,  @job.completed?
          assert_equal 6,     Jobs::TestJob.result
        end
      end

      context '.now' do
        should "process non default method (inline_mode=#{inline_mode})" do
          @job = Jobs::TestJob.now(:sum, 23, 45)
          assert_equal true,  @job.completed?, @job.inspect
          assert_equal 68,    Jobs::TestJob.result
        end
      end

    end
  end
end
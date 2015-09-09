require_relative 'test_helper'
require_relative 'jobs/test_job'

# Unit Test for RocketJob::Job
class WorkerTest < Minitest::Test
  describe RocketJob::Job do
    [true, false].each do |inline_mode|
      before do
        RocketJob::Config.inline_mode = inline_mode

        @worker = RocketJob::Worker.new
        @worker.started
      end

      after do
        @job.destroy if @job && !@job.new_record?
        RocketJob::Config.inline_mode = false
      end

      describe '.perform_later' do
        it "process single request (inline_mode=#{inline_mode})" do
          @job = Jobs::TestJob.perform_later(1) do |job|
            job.destroy_on_complete = false
          end
          assert_nil @job.worker_name
          assert_nil @job.completed_at
          assert @job.created_at
          assert_nil @job.description
          assert_equal false, @job.destroy_on_complete
          assert_nil @job.expires_at
          assert_equal 0, @job.percent_complete
          assert_equal 51, @job.priority
          assert_equal 0, @job.failure_count
          assert_nil @job.run_at
          assert_nil @job.started_at
          assert_equal :queued, @job.state

          @job.worker_name = 'me'
          @job.start
          assert_equal false, @job.work(@worker), @job.exception.inspect
          assert_equal true, @job.completed?
          assert_equal 2, Jobs::TestJob.result

          assert_nil @job.worker_name
          assert @job.completed_at
          assert @job.created_at
          assert_nil @job.description
          assert_equal false, @job.destroy_on_complete
          assert_nil @job.expires_at
          assert_equal 100, @job.percent_complete
          assert_equal 51, @job.priority
          assert_equal 0, @job.failure_count
          assert_nil @job.run_at
          assert @job.started_at
        end
      end

      describe '.later' do
        it "process non default method (inline_mode=#{inline_mode})" do
          @job = Jobs::TestJob.later(:sum, 23, 45)
          @job.start
          assert_equal false, @job.work(@worker), @job.exception.inspect
          assert_equal true, @job.completed?
          assert_equal 68, Jobs::TestJob.result
        end
      end

      describe '.perform_now' do
        it "process perform (inline_mode=#{inline_mode})" do
          @job = Jobs::TestJob.perform_now(5)
          assert_equal true, @job.completed?
          assert_equal 6, Jobs::TestJob.result
        end
      end

      describe '.now' do
        it "process non default method (inline_mode=#{inline_mode})" do
          @job = Jobs::TestJob.now(:sum, 23, 45)
          assert_equal true, @job.completed?, @job.inspect
          assert_equal 68, Jobs::TestJob.result
        end
      end

    end
  end
end

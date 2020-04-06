require_relative "../test_helper"

module Plugins
  class RetryTest < Minitest::Test
    class RetryJob < RocketJob::Job
      include RocketJob::Plugins::Retry

      # Fails 5 times before succeeding
      def perform
        raise "Oh No" unless rocket_job_failure_count >= 5

        "DONE"
      end
    end

    describe RocketJob::Plugins::Retry do
      before do
        RetryJob.delete_all
      end

      after do
        @job.delete if @job && !@job.new_record?
      end

      describe "#perform" do
        it "re-queues job on failure" do
          @job = RetryJob.create!
          assert created_at = @job.created_at
          assert_equal 0, @job.failed_at_list.size

          assert_raises RuntimeError do
            @job.perform_now
          end

          assert @job.queued?, -> { @job.attributes.ai }

          # Includes failure time
          assert_equal 1, @job.rocket_job_failure_count
          assert failed_at = @job.failed_at_list.first
          assert failed_at >= created_at

          assert next_time = @job.run_at
          assert next_time > failed_at
        end

        it "re-queues until it succeeds" do
          @job = RetryJob.create!

          # 5 retries
          5.times do |i|
            assert_raises RuntimeError do
              @job.perform_now
            end
            assert @job.queued?, -> { @job.attributes.ai }
            assert_equal (i + 1), @job.rocket_job_failure_count
          end

          assert_equal 5, @job.rocket_job_failure_count

          # Should succeed on the 6th attempt
          @job.perform_now
          assert @job.completed?, -> { @job.attributes.ai }
          assert_equal 5, @job.rocket_job_failure_count
        end

        it "stops re-queueing after limit is reached" do
          @job = RetryJob.create!(retry_limit: 3)

          # 3 attempts are retried
          3.times do |i|
            assert_raises RuntimeError do
              @job.perform_now
            end
            assert @job.queued?, -> { @job.attributes.ai }
            assert_equal (i + 1), @job.rocket_job_failure_count
          end

          # Should fail on the 4th attempt
          assert_equal 3, @job.rocket_job_failure_count
          assert_raises RuntimeError do
            @job.perform_now
          end

          assert @job.failed?, -> { @job.attributes.ai }
        end
      end
    end
  end
end

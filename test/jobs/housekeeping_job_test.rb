require_relative '../test_helper'

module Jobs
  class HousekeepingJobTest < Minitest::Test
    class TestJob < RocketJob::Job
      def perform
      end
    end

    describe RocketJob::Jobs::HousekeepingJob do
      before do
        HousekeepingJobTest::TestJob.delete_all
        RocketJob::Jobs::HousekeepingJob.delete_all
        RocketJob::Server.delete_all
      end

      describe 'job retention' do
        before do
          job = HousekeepingJobTest::TestJob.new
          Time.stub(:now, 2.days.ago) do
            job.abort!
          end
          job = HousekeepingJobTest::TestJob.new
          Time.stub(:now, 8.days.ago) do
            job.abort!
          end

          job = HousekeepingJobTest::TestJob.new
          Time.stub(:now, 2.days.ago) do
            job.perform_now
            job.save!
          end
          job = HousekeepingJobTest::TestJob.new
          Time.stub(:now, 8.days.ago) do
            job.perform_now
            job.save!
          end

          job = HousekeepingJobTest::TestJob.new
          Time.stub(:now, 2.days.ago) do
            job.fail!
          end
          job = HousekeepingJobTest::TestJob.new
          Time.stub(:now, 15.days.ago) do
            job.fail!
          end

          job = HousekeepingJobTest::TestJob.new
          Time.stub(:now, 400.days.ago) do
            job.pause!
          end
          job = HousekeepingJobTest::TestJob.new
          job.pause!

          HousekeepingJobTest::TestJob.create!(created_at: 15.days.ago)
          HousekeepingJobTest::TestJob.create!

          assert_equal 10, HousekeepingJobTest::TestJob.count, -> { HousekeepingJobTest::TestJob.all.to_a.ai }
        end

        describe 'perform' do
          it 'destroys jobs' do
            job = RocketJob::Jobs::HousekeepingJob.new
            job.perform_now
            assert_equal 1, HousekeepingJobTest::TestJob.aborted.count, -> { HousekeepingJobTest::TestJob.aborted.to_a.ai }
            assert_equal 1, HousekeepingJobTest::TestJob.completed.count, -> { HousekeepingJobTest::TestJob.completed.to_a.ai }
            assert_equal 1, HousekeepingJobTest::TestJob.failed.count, -> { HousekeepingJobTest::TestJob.failed.to_a.ai }
            assert_equal 2, HousekeepingJobTest::TestJob.paused.count, -> { HousekeepingJobTest::TestJob.paused.to_a.ai }
            assert_equal 2, HousekeepingJobTest::TestJob.queued.count, -> { HousekeepingJobTest::TestJob.queued.to_a.ai }
          end
        end
      end

      describe 'zombie cleanup' do
        before do
          server = RocketJob::Server.new
          Time.stub(:now, 1.day.ago) do
            server.started!
          end
          assert server.reload.zombie?
          assert_equal 1, RocketJob::Server.count, -> { RocketJob::Server.all.to_a.ai }
        end

        it 'removes zombies' do
          job = RocketJob::Jobs::HousekeepingJob.new
          assert job.destroy_zombies
          job.perform_now
          assert_equal 0, RocketJob::Server.count, -> { RocketJob::Server.all.to_a.ai }
        end

        it 'leaves zombies' do
          job = RocketJob::Jobs::HousekeepingJob.new(destroy_zombies: false)
          refute job.destroy_zombies
          assert_equal 1, RocketJob::Server.count, -> { RocketJob::Server.all.to_a.ai }
          job.perform_now
          assert_equal 1, RocketJob::Server.count, -> { RocketJob::Server.all.to_a.ai }
        end
      end
    end
  end
end

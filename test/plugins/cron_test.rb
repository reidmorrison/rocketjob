require_relative '../test_helper'

module Plugins
  class CronTest < Minitest::Test
    class CronJob < RocketJob::Job
      include RocketJob::Plugins::Cron

      def perform
        'DONE'
      end
    end

    class FailOnceCronJob < RocketJob::Job
      include RocketJob::Plugins::Cron

      def perform
        raise 'oh no' if failure_count.zero?
      end
    end

    describe RocketJob::Plugins::Cron do
      before do
        # destroy_all could create new instances
        CronJob.delete_all
        FailOnceCronJob.delete_all
        assert_equal 0, CronJob.count
      end

      after do
        @job.destroy if @job && !@job.new_record?
        CronJob.delete_all
      end

      describe '#create!' do
        it 'queues a new job' do
          @job = CronJob.create!(cron_schedule: '* 1 * * *')
          assert @job.valid?
          refute @job.new_record?
        end

        describe 'timezones are supported' do
          it 'handles UTC' do
            time = Time.parse('2015-12-09 17:50:05 UTC')
            Time.stub(:now, time) do
              @job = CronJob.create!(cron_schedule: '* 1 * * * UTC')
            end
            assert @job.valid?
            refute @job.new_record?
            assert_equal Time.parse('2015-12-10 01:00:00 UTC'), @job.run_at
          end

          it 'handles Eastern' do
            time = Time.parse('2015-12-09 17:50:05 UTC')
            Time.stub(:now, time) do
              @job = CronJob.create!(cron_schedule: '* 1 * * * America/New_York')
            end
            assert @job.valid?
            refute @job.new_record?
            assert_equal Time.parse('2015-12-10 06:00:00 UTC'), @job.run_at
          end
        end
      end

      describe '#save' do
        it 'updates run_at for a new record' do
          @job = CronJob.create!(cron_schedule: '* 1 * * *')
          assert @job.run_at
        end

        it 'updates run_at for a modified record' do
          @job = CronJob.create!(cron_schedule: '* 1 * * * UTC')
          assert run_at = @job.run_at
          @job.cron_schedule = '* 2 * * * UTC'
          assert_equal run_at, @job.run_at
          @job.save!
          assert run_at != @job.run_at, @job.attributes
        end
      end

      describe '#valid?' do
        it 'allows missing cron schedule' do
          @job = CronJob.new
          assert @job.valid?
        end

        it 'fails on bad cron schedule' do
          @job = CronJob.new(cron_schedule: 'blah')
          refute @job.valid?
          assert_equal "not a valid cronline : 'blah'", @job.errors.messages[:cron_schedule].first
        end

        it 'passes on valid cron schedule' do
          @job = CronJob.new(cron_schedule: '* 1 * * *')
          assert @job.valid?
        end
      end

      describe '#fail' do
        describe 'with cron_schedule' do
          let :job do
            job = FailOnceCronJob.create!(cron_schedule: '* 1 * * *')
            job.start
            assert_raises RuntimeError do
              job.perform_now
            end
            job.reload
            job
          end

          it 'allows current cron job instance to fail' do
            assert job.failed?
          end

          it 'clears out cron_schedule' do
            refute job.cron_schedule
          end

          it 'retains run_at' do
            assert job.run_at
          end

          it 'schedules a new instance' do
            assert_equal 0, FailOnceCronJob.count
            job
            assert_equal 2, FailOnceCronJob.count
            assert scheduled_job = FailOnceCronJob.last
            assert scheduled_job.queued?
            assert_equal '* 1 * * *', scheduled_job.cron_schedule
          end

          it 'restarts on retry' do
            job.retry!
            job.perform_now
            assert job.completed?
            assert_equal 1, FailOnceCronJob.count, -> { FailOnceCronJob.all.to_a.collect(&:state).to_s }
            assert_equal 1, FailOnceCronJob.queued.count
          end
        end

        describe 'without cron_schedule' do
          let :job do
            job = CronJob.create!
            job.start
            job.fail
            job
          end

          it 'allows current cron job instance to fail' do
            assert job.failed?
          end

          it 'has no cron_schedule' do
            refute job.cron_schedule
          end

          it 'does not schedule a new instance' do
            assert_equal 0, CronJob.count
            job
            assert_equal 1, CronJob.count
          end
        end
      end
    end
  end
end

require_relative '../test_helper'

# Unit Test for RocketJob::Job
module Plugins
  class CronTest < Minitest::Test
    class CronJob < RocketJob::Job
      include RocketJob::Plugins::Cron

      def perform
        'DONE'
      end
    end

    describe RocketJob::Plugins::Cron do
      before do
        # destroy_all could create new instances
        CronJob.delete_all
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
            time = Time.parse('2015-12-09 17:50:05 +0000')
            Time.stub(:now, time) do
              @job = CronJob.create!(cron_schedule: '* 1 * * * UTC')
            end
            assert @job.valid?
            refute @job.new_record?
            assert_equal Time.parse('2015-12-10 01:00:00 UTC'), @job.run_at
          end

          it 'handles Eastern' do
            time = Time.parse('2015-12-09 17:50:05 +0000')
            Time.stub(:now, time) do
              @job = CronJob.create!(cron_schedule: '* 1 * * * America/New_York')
            end
            assert @job.valid?
            refute @job.new_record?
            assert_equal Time.parse('2015-12-10 06:00:00 UTC'), @job.run_at
          end
        end

      end

      describe '#valid?' do
        it 'fails on missing cron schedule' do
          @job = CronJob.new
          refute @job.valid?
          assert_equal "can't be blank", @job.errors.messages[:cron_schedule].first
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

    end
  end
end

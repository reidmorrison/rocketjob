require_relative '../test_helper'

# Unit Test for RocketJob::Job
module Concerns
  class CronTest < Minitest::Test
    class CronJob < RocketJob::Job
      include RocketJob::Concerns::Cron

      def perform
        'DONE'
      end
    end

    describe RocketJob::Concerns::Restart do
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
      end

      describe '#valid?' do
        it 'fails on missing cron schedule' do
          @job = CronJob.new
          refute @job.valid?
          assert_equal "can't be blank",  @job.errors.messages[:cron_schedule].first
        end

        it 'fails on bad cron schedule' do
          @job = CronJob.new(cron_schedule: 'blah')
          refute @job.valid?
          assert_equal "not a valid cronline : 'blah'",  @job.errors.messages[:cron_schedule].first
        end

        it 'passes on valid cron schedule' do
          @job = CronJob.new(cron_schedule: '* 1 * * *')
          assert @job.valid?
        end

      end

    end
  end
end

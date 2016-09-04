require_relative '../test_helper'

# Unit Test for RocketJob::Job
module Plugins
  class ProcessingWindowTest < Minitest::Test
    class ProcessingWindowJob < RocketJob::Job
      include RocketJob::Plugins::ProcessingWindow

      def perform
        'DONE'
      end
    end

    describe RocketJob::Plugins::ProcessingWindow do
      before do
        # destroy_all could create new instances
        ProcessingWindowJob.delete_all
        assert_equal 0, ProcessingWindowJob.count
      end

      after do
        @job.destroy if @job && !@job.new_record?
        ProcessingWindowJob.delete_all
      end

      describe '#create!' do
        it 'queues a new job' do
          @job = ProcessingWindowJob.create!(processing_schedule: '* 1 * * *', processing_duration: 1.hour)
          assert @job.valid?
          refute @job.new_record?
        end

        describe 'timezones are supported' do
          it 'handles UTC' do
            time = Time.parse('2015-12-09 17:50:05 +0000')
            Time.stub(:now, time) do
              @job = ProcessingWindowJob.create!(processing_schedule: '* 1 * * * UTC', processing_duration: 1.hour)
            end
            assert @job.valid?
            refute @job.new_record?
            assert_equal Time.parse('2015-12-10 01:00:00 UTC'), @job.run_at
          end

          it 'handles Eastern' do
            time = Time.parse('2015-12-09 17:50:05 +0000')
            Time.stub(:now, time) do
              @job = ProcessingWindowJob.create!(processing_schedule: '* 1 * * * America/New_York', processing_duration: 1.hour)
            end
            assert @job.valid?
            refute @job.new_record?
            assert_equal Time.parse('2015-12-10 06:00:00 UTC'), @job.run_at
          end
        end
      end

      describe '#rocket_job_processing_window_active?' do
        it 'returns true when in the processing window' do
          time   = Time.parse('2015-12-09 17:50:05 +0000')
          @job   = ProcessingWindowJob.new(processing_schedule: '* 17 * * * UTC', processing_duration: 1.hour)
          result = Time.stub(:now, time) do
            @job.rocket_job_processing_window_active?
          end
          assert result, @job.attributes.ai
        end

        it 'returns false when not in the processing window' do
          time   = Time.parse('2015-12-09 16:50:05 +0000')
          @job   = ProcessingWindowJob.new(processing_schedule: '* 17 * * * UTC', processing_duration: 1.hour)
          result = Time.stub(:now, time) do
            @job.rocket_job_processing_window_active?
          end
          refute result, @job.attributes.ai
        end
      end

      describe '#valid?' do
        it 'fails on missing processing_schedule' do
          @job = ProcessingWindowJob.new
          refute @job.valid?
          assert_equal "can't be blank", @job.errors.messages[:processing_schedule].first
          assert_equal 'not a string: nil', @job.errors.messages[:processing_schedule].second
          assert_equal "can't be blank", @job.errors.messages[:processing_duration].first
        end

        it 'fails on bad cron schedule' do
          @job = ProcessingWindowJob.new(processing_schedule: 'blah')
          refute @job.valid?
          assert_equal "not a valid cronline : 'blah'", @job.errors.messages[:processing_schedule].first
        end

        it 'passes on valid cron schedule' do
          @job = ProcessingWindowJob.new(processing_schedule: '* 1 * * *', processing_duration: 1.hour)
          assert @job.valid?
        end
      end

      describe 're-queue' do
        it 'if outside processing window' do
          time = Time.parse('2015-12-09 16:50:05 +0000')
          Time.stub(:now, time) do
            @job = ProcessingWindowJob.new(processing_schedule: '* 17 * * * UTC', processing_duration: 1.hour)
            @job.perform_now
          end
          assert @job.queued?, @job.attributes.ai
        end
      end

    end

  end
end

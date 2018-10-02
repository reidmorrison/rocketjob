require_relative '../test_helper'

# Unit Test for RocketJob::Job
module Plugins
  module Batch
    class LoggerTest < Minitest::Test
      class LoggerJob < RocketJob::Job
        include RocketJob::Batch

        def perform(record)
          logger.debug('DONE', value: 123, record: record)
        end
      end

      describe RocketJob::Batch::Logger do
        before do
          LoggerJob.delete_all
        end

        after do
          @job.destroy if @job && !@job.new_record?
          SemanticLogger.flush
        end

        describe '#logger' do
          it 'uses semantic logger' do
            @job = LoggerJob.new
            assert_kind_of SemanticLogger::Logger, @job.logger, @job.logger.ai
            assert_equal @job.class.name, @job.logger.name, @job.logger.ai
          end

          it 'allows perform to log its own data' do
            @job = LoggerJob.new
            @job.perform_now
          end

          it 'adds start logging' do
            @job = LoggerJob.new
            @job.upload do |stream|
              stream << 'first'
              stream << 'second'
            end
            info_called = false
            @job.logger.stub(:info, ->(description, _payload) { info_called = true if description == 'Start' }) do
              @job.perform_now
            end
            assert info_called, "In Plugins::Batch::Logger.rocket_job_batch_log_state_change logger.info('Start') not called"
          end

          it 'adds completed logging' do
            @job = LoggerJob.new
            @job.upload do |stream|
              stream << 'first'
              stream << 'second'
            end
            measure_called = false
            @job.logger.stub(:measure_info, ->(description, *_args) { measure_called = true if description.include?('Completed slice') }) do
              @job.perform_now
            end
            assert measure_called, "In Plugins::Batch::Logger.around_slice logger.measure_info('Completed slice') not called"
          end

          it 'logs state transitions' do
            @job        = LoggerJob.new
            description = nil
            payload     = nil
            @job.logger.stub(:info, ->(_description, _payload) { description = _description, payload = _payload }) do
              @job.start
            end

            assert_equal 'Start', description.first
            assert_equal :start, payload[:event]
            assert_equal :queued, payload[:from]
            assert_equal :running, payload[:to]
          end
        end
      end
    end
  end
end

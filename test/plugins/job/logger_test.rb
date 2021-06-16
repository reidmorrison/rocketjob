require_relative "../../test_helper"

module Plugins
  module Job
    class LoggerTest < Minitest::Test
      class LoggerJob < RocketJob::Job
        def perform
          logger.debug("DONE", value: 123, other_value: "HI")
        end
      end

      describe RocketJob::Plugins::Job::Logger do
        before do
          LoggerJob.delete_all
        end

        after do
          @job.destroy if @job && !@job.new_record?
          SemanticLogger.flush
        end

        describe "#logger" do
          it "uses semantic logger" do
            @job = LoggerJob.new
            assert_kind_of SemanticLogger::Logger, @job.logger, @job.logger.ai
            assert_equal @job.class.name, @job.logger.name, @job.logger.ai
          end

          it "allows perform to log its own data" do
            @job = LoggerJob.new
            @job.perform_now
          end

          it "adds start logging" do
            @job        = LoggerJob.new
            info_called = false
            @job.logger.stub(:info, ->(description) { info_called = true if description == "Start #perform" }) do
              @job.perform_now
            end
            assert info_called, "In Plugins::Job::Logger.around_perform logger.info('Start #perform') not called"
          end

          it "adds completed logging" do
            @job           = LoggerJob.new
            measure_called = false
            @job.logger.stub(:measure_info, lambda { |description, *_args|
              measure_called = true if description == "Completed #perform"
            }) do
              @job.perform_now
            end
            assert measure_called, "In Plugins::Job::Logger.around_perform logger.measure_info('Completed #perform') not called"
          end
        end
      end
    end
  end
end

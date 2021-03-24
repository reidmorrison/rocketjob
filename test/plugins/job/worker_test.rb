require_relative "../../test_helper"

module Plugins
  module Job
    class WorkerTest < Minitest::Test
      class QuietJob < RocketJob::Job
        # Test increasing log level for debugging purposes
        def perform
          logger.trace "enable tracing level for just the job instance"
        end
      end

      class NoisyJob < RocketJob::Job
        # Test silencing noisy logging
        def perform
          logger.info "some very noisy logging"
        end
      end

      class SumJob < RocketJob::Job
        self.destroy_on_complete = false
        self.priority            = 51

        field :first, type: Integer
        field :second, type: Integer
        field :result, type: Integer

        def perform
          self.result = first + second
        end
      end

      describe RocketJob::Plugins::Job::Worker do
        before do
          RocketJob::Job.delete_all
          RocketJob::Server.delete_all
        end

        after do
          @job.destroy if @job && !@job.new_record?
        end

        describe "#perform_now" do
          it "calls perform method" do
            @job = SumJob.new(first: 10, second: 5)
            assert_equal 15, @job.perform_now
            assert @job.completed?, @job.attributes.ai
            assert_equal 15, @job.result
          end

          it "converts type" do
            @job = SumJob.new(first: "10", second: 5)
            assert_equal 15, @job.perform_now
            assert @job.completed?, @job.attributes.ai
            assert_equal 15, @job.result
          end

          it "silence logging when log_level is set" do
            @job           = NoisyJob.new
            @job.log_level = :warn
            logged         = false
            @job.logger.stub(:log_internal, lambda { |_level, _index, message, _payload, _exception|
                                              logged = true if message.include?("some very noisy logging")
                                            }) do
              @job.perform_now
            end
            assert_equal false, logged
          end

          it "raise logging when log_level is set" do
            @job           = QuietJob.new
            @job.log_level = :trace
            logged         = false
            # Raise global log level to :info
            SemanticLogger.stub(:default_level_index, 3) do
              @job.logger.stub(:log_internal, -> { logged = true }) do
                @job.perform_now
              end
            end
            assert_equal false, logged
          end
        end

        describe ".perform_now" do
          it "run the job immediately" do
            @job = SumJob.perform_now(first: 1, second: 5)
            assert_equal true, @job.completed?
            assert_equal 6, @job.result
          end
        end

        describe "#rocket_job_active_workers" do
          it "should return empty hash for no active jobs" do
            assert_equal([], QuietJob.create!.rocket_job_active_workers)
          end

          it "should return active servers" do
            assert job = SumJob.new(worker_name: "worker:123")
            job.start!
            assert active = job.rocket_job_active_workers
            assert_equal 1, active.size
            assert active_worker = active.first
            assert_equal job.id, active_worker.job.id
            assert_equal "worker:123", active_worker.name
            assert_equal job.started_at, active_worker.started_at
            assert active_worker.duration_s
            assert active_worker.duration
          end
        end
      end
    end
  end
end

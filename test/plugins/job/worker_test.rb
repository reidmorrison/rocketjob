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

      class FailingJob < RocketJob::Job
        self.destroy_on_complete = false

        def perform
          raise "Job failed"
        end
      end

      class ValidationJob < RocketJob::Job
        field :name, type: String
        validates_presence_of :name

        def perform
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
            assert_predicate @job, :completed?, @job.attributes.ai
            assert_equal 15, @job.result
          end

          it "converts type" do
            @job = SumJob.new(first: "10", second: 5)

            assert_equal 15, @job.perform_now
            assert_predicate @job, :completed?, @job.attributes.ai
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

            refute logged
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

            refute logged
          end

          it "raises a validation error for an invalid job" do
            @job = ValidationJob.new
            assert_raises Mongoid::Errors::Validations do
              @job.perform_now
            end
            refute_predicate @job, :completed?
          end

          it "re-raises exceptions from perform" do
            @job = FailingJob.new
            error = assert_raises RuntimeError do
              @job.perform_now
            end
            assert_equal "Job failed", error.message
          end
        end

        describe ".perform_now" do
          it "run the job immediately" do
            @job = SumJob.perform_now(first: 1, second: 5)

            assert_predicate @job, :completed?
            assert_equal 6, @job.result
          end
        end

        describe "#perform" do
          it "raises NotImplementedError when not overridden" do
            assert_raises NotImplementedError do
              RocketJob::Job.new.perform
            end
          end
        end

        describe "#rocket_job_work" do
          it "raises an ArgumentError when the job is not running" do
            @job = SumJob.new(first: 1, second: 2)

            assert_predicate @job, :queued?
            error = assert_raises ArgumentError do
              @job.rocket_job_work(RocketJob::Worker.new)
            end
            assert_includes error.message, "must be started"
          end

          it "fails the job and persists it when perform raises" do
            @job = FailingJob.create!
            @job.start!

            refute @job.rocket_job_work(RocketJob::Worker.new)
            @job.reload

            assert_predicate @job, :failed?, @job.state
            assert_equal "Job failed", @job.exception.message
          end

          it "completes a persisted job" do
            @job = SumJob.create!(first: 3, second: 4)
            @job.start!

            refute @job.rocket_job_work(RocketJob::Worker.new)
            @job.reload

            assert_predicate @job, :completed?, @job.state
            assert_equal 7, @job.result
          end
        end

        describe "#fail_on_exception!" do
          it "fails and saves the job when the block raises" do
            @job = SumJob.create!(first: 1, second: 2, worker_name: "worker:123")
            @job.start!
            @job.fail_on_exception! do
              raise "boom"
            end

            assert_predicate @job, :failed?, @job.state
            @job.reload

            assert_predicate @job, :failed?, @job.state
            assert_equal "boom", @job.exception.message
            assert_equal "worker:123", @job.exception.worker_name
          end

          it "re-raises the exception when requested" do
            @job = SumJob.create!(first: 1, second: 2)
            @job.start!
            assert_raises RuntimeError do
              @job.fail_on_exception!(true) do
                raise "boom"
              end
            end
            assert_predicate @job, :failed?, @job.state
          end

          it "does not transition an already failed job but records the exception" do
            @job = SumJob.create!(first: 1, second: 2, worker_name: "worker:123")
            @job.start!
            @job.fail!("worker:123", "first failure")

            assert_predicate @job, :failed?, @job.state

            @job.fail_on_exception! do
              raise "second failure"
            end

            assert_predicate @job, :failed?, @job.state
            assert_equal "second failure", @job.exception.message
          end

          it "does nothing when the block does not raise" do
            @job = SumJob.create!(first: 1, second: 2)
            @job.start!
            ran = false
            @job.fail_on_exception! do
              ran = true
            end

            assert ran
            refute_predicate @job, :failed?
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

          it "returns the worker when it runs on the named server" do
            @job = SumJob.new(worker_name: "worker:123")
            @job.start!

            assert_equal 1, @job.rocket_job_active_workers("worker").size
          end

          it "returns empty when the worker is not on the named server" do
            @job = SumJob.new(worker_name: "worker:123")
            @job.start!

            assert_equal [], @job.rocket_job_active_workers("other_server")
          end
        end
      end
    end
  end
end

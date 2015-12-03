require_relative '../test_helper'

# Unit Test for RocketJob::Job
class WorkerTest < Minitest::Test
  class QuietJob < RocketJob::Job
    # Test increasing log level for debugging purposes
    def perform
      logger.trace 'enable tracing level for just the job instance'
    end
  end

  class NoisyJob < RocketJob::Job
    # Test silencing noisy logging
    def perform
      logger.info 'some very noisy logging'
    end
  end

  describe RocketJob::Concerns::Worker do
    describe '.next_job' do
      before do
        RocketJob::Job.destroy_all
        @quiet_job = QuietJob.new
      end

      after do
        @quiet_job.destroy if @quiet_job && !@quiet_job.new_record?
      end

      it 'return nil when no jobs available' do
        assert_equal nil, RocketJob::Job.next_job(@worker.name)
      end

      it 'return the first job' do
        @job.save!
        assert job = RocketJob::Job.next_job(@worker.name), 'Failed to find job'
        assert_equal @job.id, job.id
      end

      it 'Ignore future dated jobs' do
        @job.run_at = Time.now + 1.hour
        @job.save!
        assert_equal nil, RocketJob::Job.next_job(@worker.name)
      end

      it 'Process future dated jobs when time is now' do
        @job.run_at = Time.now
        @job.save!
        assert job = RocketJob::Job.next_job(@worker.name), 'Failed to find future job'
        assert_equal @job.id, job.id
      end

      it 'Skip expired jobs' do
        count           = RocketJob::Job.count
        @job.expires_at = Time.now - 100
        @job.save!
        assert_equal nil, RocketJob::Job.next_job(@worker.name)
        assert_equal count, RocketJob::Job.count
      end
    end

    describe '#work' do
      it 'call perform method' do
        assert_equal false, @sum_job.perform_now
        assert_equal true, @sum_job.completed?, @job.state
        assert_equal 15, Jobs::SumJob.result
        assert_equak 15, @sum_job.output
      end

      it 'silence logging when log_level is set' do
        @noisy_job.destroy_on_complete = true
        @noisy_job.log_level           = :warn
        @noisy_job.arguments           = []
        @noisy_job.start!
        logged = false
        Jobs::TestJob.logger.stub(:log_internal, -> level, index, message, payload, exception { logged = true if message.include?('some very noisy logging') }) do
          assert_equal false, @noisy_job.work(@worker), @noisy_job.inspect
        end
        assert_equal false, logged
      end

      it 'raise logging when log_level is set' do
        @quiet_job.destroy_on_complete = true
        @quiet_job.log_level           = :trace
        @quiet_job.arguments           = []
        @quiet_job.start!
        logged = false
        # Raise global log level to :info
        SemanticLogger.stub(:default_level_index, 3) do
          Jobs::TestJob.logger.stub(:log_internal, -> { logged = true }) do
            assert_equal false, @quiet_job.work(@worker)
          end
        end
        assert_equal false, logged
      end
    end

    [true, false].each do |inline_mode|
      before do
        RocketJob::Config.inline_mode = inline_mode

        @worker = RocketJob::Worker.new
        @worker.started
      end

      after do
        @job.destroy if @job && !@job.new_record?
        RocketJob::Config.inline_mode = false
      end

      describe '.perform_later' do
        it "process single request (inline_mode=#{inline_mode})" do
          @job = Jobs::TestJob.perform_later(1) do |job|
            job.destroy_on_complete = false
          end
          assert_nil @job.worker_name
          assert_nil @job.completed_at
          assert @job.created_at
          assert_equal false, @job.destroy_on_complete
          assert_nil @job.expires_at
          assert_equal 0, @job.percent_complete
          assert_equal 51, @job.priority
          assert_equal 0, @job.failure_count
          assert_nil @job.run_at
          assert_nil @job.started_at
          assert_equal :queued, @job.state

          @job.worker_name = 'me'
          @job.start
          assert_equal false, @job.work(@worker), @job.exception.inspect
          assert_equal true, @job.completed?
          assert_equal 2, Jobs::TestJob.result

          assert_nil @job.worker_name
          assert @job.completed_at
          assert @job.created_at
          assert_equal false, @job.destroy_on_complete
          assert_nil @job.expires_at
          assert_equal 100, @job.percent_complete
          assert_equal 51, @job.priority
          assert_equal 0, @job.failure_count
          assert_nil @job.run_at
          assert @job.started_at
        end
      end

      describe '.later' do
        it "process non default method (inline_mode=#{inline_mode})" do
          @job = Jobs::TestJob.later(:sum, 23, 45)
          @job.start
          assert_equal false, @job.work(@worker), @job.exception.inspect
          assert_equal true, @job.completed?
          assert_equal 68, Jobs::TestJob.result
        end
      end

      describe '.perform_now' do
        it "process perform (inline_mode=#{inline_mode})" do
          @job = Jobs::TestJob.perform_now(5)
          assert_equal true, @job.completed?
          assert_equal 6, Jobs::TestJob.result
        end
      end

      describe '.now' do
        it "process non default method (inline_mode=#{inline_mode})" do
          @job = Jobs::TestJob.now(:sum, 23, 45)
          assert_equal true, @job.completed?, @job.inspect
          assert_equal 68, Jobs::TestJob.result
        end
      end

    end
  end
end

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

  class SumJob < RocketJob::Job
    rocket_job do |job|
      job.destroy_on_complete = false
      job.collect_output      = true
      job.priority            = 51
    end

    def perform(first, second)
      first + second
    end
  end

  describe RocketJob::Concerns::Worker do
    before do
      RocketJob::Job.destroy_all
    end

    after do
      @job.destroy if @job && !@job.new_record?
    end

    describe '.next_job' do
      before do
        @job = QuietJob.new
        @worker = RocketJob::Worker.new(name: 'worker:123')
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
      it 'calls perform method' do
        @job = SumJob.new(arguments: [10, 5])
        assert_equal 15, @job.perform_now['result']
        assert @job.completed?, @job.attributes.ai
        assert_equal 15, @job.result['result']
      end

      it 'silence logging when log_level is set' do
        @job                     = NoisyJob.new
        @job.log_level           = :warn
        logged = false
        @job.logger.stub(:log_internal, -> level, index, message, payload, exception { logged = true if message.include?('some very noisy logging') }) do
          @job.perform_now
        end
        assert_equal false, logged
      end

      it 'raise logging when log_level is set' do
        @job                     = QuietJob.new
        @job.log_level           = :trace
        logged = false
        # Raise global log level to :info
        SemanticLogger.stub(:default_level_index, 3) do
          @job.logger.stub(:log_internal, -> { logged = true }) do
            @job.perform_now
          end
        end
        assert_equal false, logged
      end
    end

    describe '.perform_later' do
      it 'queues the job for processing' do
        RocketJob::Config.stub(:inline_mode, false) do
          @job = SumJob.perform_later(1, 23)
        end
        assert @job.queued?

        # Manually run the job
        @job.perform_now
        assert @job.completed?, @job.attributes.ai
        assert_equal 24, @job.result['result']

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

      it 'runs the job immediately when inline_mode = true' do
        RocketJob::Config.stub(:inline_mode, true) do
          @job = SumJob.perform_later(1, 23)
        end

        assert @job.completed?, @job.attributes.ai
        assert_equal 24, @job.result['result']

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

    describe '.perform_now' do
      it 'run the job immediately' do
        @job = SumJob.perform_now(1,5)
        assert_equal true, @job.completed?
        assert_equal 6, @job.result['result']
      end
    end

  end
end

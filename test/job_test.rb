require_relative 'test_helper'
require_relative 'jobs/test_job'

# Unit Test for RocketJob::Job
class JobTest < Minitest::Test
  context RocketJob::Job do
    setup do
      @worker = RocketJob::Worker.new
      @worker.started
      @description = 'Hello World'
      @arguments   = [1]
      @job         = Jobs::TestJob.new(
        description:         @description,
        arguments:           @arguments,
        destroy_on_complete: false
      )
      @job2        = Jobs::TestJob.new(
        description:         "#{@description} 2",
        arguments:           @arguments,
        destroy_on_complete: false
      )
    end

    teardown do
      @job.destroy if @job && !@job.new_record?
      @job2.destroy if @job2 && !@job2.new_record?
    end

    context '.config' do
      should 'support multiple databases' do
        assert_equal 'test_rocketjob', RocketJob::Job.collection.db.name
      end
    end

    context '#reload' do
      should 'handle hash' do
        @job = Jobs::TestJob.new(
          description:         @description,
          arguments:           [{key: 'value'}],
          destroy_on_complete: false,
          worker_name:         'worker:123'
        )

        assert_equal 'value', @job.arguments.first[:key]
        @job.worker_name = nil
        @job.save!
        @job.worker_name = '123'
        @job.reload
        assert @job.arguments.first.is_a?(ActiveSupport::HashWithIndifferentAccess), @job.arguments.first.class.inspect
        assert_equal 'value', @job.arguments.first['key']
        assert_equal 'value', @job.arguments.first[:key]
        assert_equal nil, @job.worker_name
      end
    end

    context '#save!' do
      should 'save a blank job' do
        @job.save!
        assert_nil @job.worker_name
        assert_nil @job.completed_at
        assert @job.created_at
        assert_equal @description, @job.description
        assert_equal false, @job.destroy_on_complete
        assert_nil @job.expires_at
        assert_equal @arguments, @job.arguments
        assert_equal 0, @job.percent_complete
        assert_equal 50, @job.priority
        assert_equal 0, @job.failure_count
        assert_nil @job.run_at
        assert_nil @job.started_at
        assert_equal :queued, @job.state
      end
    end

    context '#status' do
      should 'return status for a queued job' do
        assert_equal true, @job.queued?
        h = @job.status
        assert_equal :queued, h['state']
        assert_equal @description, h['description']
      end

      should 'return status for a failed job' do
        @job.start!
        @job.fail!('worker:1234', 'oh no')
        assert_equal true, @job.failed?
        h = @job.status
        assert_equal :failed, h['state']
        assert_equal @description, h['description']
        assert_equal 'RocketJob::JobException', h['exception']['class_name'], h
        assert_equal 'oh no', h['exception']['message'], h
      end

      should 'mark user as reason for failure when not supplied' do
        @job.start!
        @job.fail!
        assert_equal true, @job.failed?
        assert_equal @description, @job.description
        assert_equal 'RocketJob::JobException', @job.exception.class_name
        assert_equal 'Job failed through user action', @job.exception.message
        assert_equal 'user', @job.exception.worker_name
      end
    end

    context '#fail_with_exception!' do
      should 'fail with message' do
        @job.start!
        @job.fail!('myworker:2323', 'oh no')
        assert_equal true, @job.failed?
        h = @job.status
        assert_equal :failed, h['state']
        assert_equal @description, h['description']
        assert_equal 'RocketJob::JobException', h['exception']['class_name'], h
        assert_equal 'oh no', h['exception']['message'], h
      end

      should 'fail with exception' do
        @job.start!
        exception = nil
        begin
          blah
        rescue Exception => exc
          exception = exc
        end
        @job.fail!('myworker:2323', exception)
        assert_equal true, @job.failed?
        h = @job.status
        assert_equal :failed, h['state']
        assert_equal @description, h['description']
        assert_equal exception.class.name.to_s, h['exception']['class_name'], h
        assert h['exception']['message'].include?('undefined local variable or method'), h
      end
    end

    context '#work' do
      should 'call default perform method' do
        @job.start!
        assert_equal false, @job.work(@worker)
        assert_equal true, @job.completed?, @job.state
        assert_equal 2, Jobs::TestJob.result
      end

      should 'call specific method' do
        @job.perform_method = :sum
        @job.arguments      = [23, 45]
        @job.start!
        assert_equal false, @job.work(@worker)
        assert_equal true, @job.completed?
        assert_equal 68, Jobs::TestJob.result
      end

      should 'destroy on complete' do
        @job.destroy_on_complete = true
        @job.start!
        assert_equal false, @job.work(@worker)
        assert_equal nil, RocketJob::Job.find_by_id(@job.id)
      end

      should 'silence logging when log_level is set' do
        @job.destroy_on_complete = true
        @job.log_level           = :warn
        @job.perform_method      = :noisy_logger
        @job.arguments           = []
        @job.start!
        logged = false
        Jobs::TestJob.logger.stub(:log_internal, -> level, index, message, payload, exception { logged = true if message.include?('some very noisy logging') }) do
          assert_equal false, @job.work(@worker), @job.inspect
        end
        assert_equal false, logged
      end

      should 'raise logging when log_level is set' do
        @job.destroy_on_complete = true
        @job.log_level           = :trace
        @job.perform_method      = :debug_logging
        @job.arguments           = []
        @job.start!
        logged = false
        # Raise global log level to :info
        SemanticLogger.stub(:default_level_index, 3) do
          Jobs::TestJob.logger.stub(:log_internal, -> { logged = true }) do
            assert_equal false, @job.work(@worker)
          end
        end
        assert_equal false, logged
      end

      should 'call before and after' do
        named_parameters    = {'counter' => 23}
        @job.perform_method = :event
        @job.arguments      = [named_parameters]
        @job.start!
        assert_equal false, @job.work(@worker), @job.inspect
        assert_equal true, @job.completed?
        assert_equal named_parameters.merge('before_event' => true, 'after_event' => true), @job.arguments.first
      end

    end

    context '.next_job' do
      setup do
        RocketJob::Job.destroy_all
      end

      should 'return nil when no jobs available' do
        assert_equal nil, RocketJob::Job.next_job(@worker.name)
      end

      should 'return the first job' do
        @job.save!
        assert job = RocketJob::Job.next_job(@worker.name), 'Failed to find job'
        assert_equal @job.id, job.id
      end

      should 'Ignore future dated jobs' do
        @job.run_at = Time.now + 1.hour
        @job.save!
        assert_equal nil, RocketJob::Job.next_job(@worker.name)
      end

      should 'Process future dated jobs when time is now' do
        @job.run_at = Time.now
        @job.save!
        assert job = RocketJob::Job.next_job(@worker.name), 'Failed to find future job'
        assert_equal @job.id, job.id
      end

      should 'Skip expired jobs' do
        count           = RocketJob::Job.count
        @job.expires_at = Time.now - 100
        @job.save!
        assert_equal nil, RocketJob::Job.next_job(@worker.name)
        assert_equal count, RocketJob::Job.count
      end
    end

    context '#requeue!' do
      should 'requeue jobs from dead workers' do
        worker_name      = 'server:12345'
        @job.worker_name = worker_name
        @job.start!
        assert @job.running?

        @job.requeue!
        @job.reload

        assert @job.queued?
        assert_equal nil, @job.worker_name
      end
    end

    context '#requeue' do
      should 'requeue jobs from dead workers' do
        worker_name      = 'server:12345'
        @job.worker_name = worker_name
        @job.start!
        assert @job.running?

        @job.requeue
        assert @job.queued?
        assert_equal nil, @job.worker_name

        @job.reload
        assert @job.running?
        assert_equal worker_name, @job.worker_name
      end
    end

    context '.requeue_dead_worker' do
      should 'requeue jobs from dead workers' do
        worker_name      = 'server:12345'
        @job.worker_name = worker_name
        @job.start!
        assert @job.running?

        worker_name2      = 'server:76467'
        @job2.worker_name = worker_name2
        @job2.start!

        RocketJob::Job.requeue_dead_worker(worker_name)
        @job.reload

        assert @job.queued?
        assert_equal nil, @job.worker_name

        @job2.reload
        assert @job2.running?
        assert_equal worker_name2, @job2.worker_name
      end
    end

    context '#retry!' do
      should 'retry failed jobs' do
        worker_name      = 'server:12345'
        @job.worker_name = worker_name
        @job.start!
        assert @job.running?
        assert_equal worker_name, @job.worker_name

        @job.fail!(worker_name, 'oh no')
        assert @job.failed?

        @job.retry!
        assert @job.queued?
        assert_equal nil, @job.worker_name
      end
    end

  end
end

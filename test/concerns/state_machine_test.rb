require_relative '../test_helper'

# Unit Test for RocketJob::Job
class StateMachineTest < Minitest::Test

  class StateMachineJob < RocketJob::Job
    def perform
    end
  end

  describe RocketJob::Concerns::StateMachine do
    before do
      @job = StateMachineJob.new
    end

    after do
      @job.destroy if @job && !@job.new_record?
    end

    describe '#requeue!' do
      it 'requeue jobs from dead workers' do
        worker_name      = 'server:12345'
        @job.worker_name = worker_name
        @job.start!
        assert @job.running?

        @job.requeue!(worker_name)
        @job.reload

        assert @job.queued?
        assert_equal nil, @job.worker_name
      end
    end

    describe '#requeue' do
      it 'requeue jobs from dead workers' do
        worker_name      = 'server:12345'
        @job.worker_name = worker_name
        assert @job.valid?, @job.errors.messages
        @job.start!
        assert @job.running?, @job.state

        @job.requeue(worker_name)
        assert @job.queued?
        assert_equal nil, @job.worker_name

        @job.reload
        assert @job.running?
        assert_equal worker_name, @job.worker_name
      end
    end

    describe '#after_complete' do
      it 'destroy on complete' do
        @job.destroy_on_complete = true
        @job.start!
        assert_equal false, @job.work(@worker)
        assert @job.completed?, @job.state
        assert_equal 0, RocketJob::Job.where(id: @job.id).count
      end
    end

    describe '#fail!' do
      it 'fail with message' do
        @job.start!
        @job.fail!('myworker:2323', 'oh no')
        assert_equal true, @job.failed?
        h = @job.status
        assert_equal :failed, h['state']
        assert_equal 'RocketJob::JobException', h['exception']['class_name'], h
        assert_equal 'oh no', h['exception']['message'], h
      end

      it 'fail with exception' do
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
        assert_equal exception.class.name.to_s, h['exception']['class_name'], h
        assert h['exception']['message'].include?('undefined local variable or method'), h
      end
    end

    describe '#retry!' do
      it 'retry failed jobs' do
        worker_name      = 'server:12345'
        @job.worker_name = worker_name
        @job.start!
        assert @job.running?
        assert_equal worker_name, @job.worker_name

        @job.fail!(worker_name, 'oh no')
        assert @job.failed?
        assert_equal 'oh no', @job.exception.message

        @job.retry!
        assert @job.queued?
        assert_equal nil, @job.worker_name
        assert_equal nil, @job.exception
      end
    end

  end
end

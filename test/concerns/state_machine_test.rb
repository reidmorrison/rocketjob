require_relative '../test_helper'
require_relative '../jobs/test_job'

# Unit Test for RocketJob::Job
class JobTest < Minitest::Test
  describe RocketJob::Concerns::StateMachine do
    before do
      @description = 'Hello World'
      @quiet_job   = Jobs::QuietJob.new(
        description: @description,
        worker_name: 'worker:123'
      )
    end

    after do
      @quiet_job.destroy if @quiet_job && !@quiet_job.new_record?
    end

    describe '#requeue!' do
      it 'requeue jobs from dead workers' do
        worker_name      = 'server:12345'
        @quiet_job.worker_name = worker_name
        @quiet_job.start!
        assert @quiet_job.running?

        @quiet_job.requeue!(worker_name)
        @quiet_job.reload

        assert @quiet_job.queued?
        assert_equal nil, @quiet_job.worker_name
      end
    end

    describe '#requeue' do
      it 'requeue jobs from dead workers' do
        worker_name      = 'server:12345'
        @quiet_job.worker_name = worker_name
        assert @quiet_job.valid?, @quiet_job.errors.messages
        @quiet_job.start!
        assert @quiet_job.running?, @quiet_job.state

        @quiet_job.requeue(worker_name)
        assert @quiet_job.queued?
        assert_equal nil, @quiet_job.worker_name

        @quiet_job.reload
        assert @quiet_job.running?
        assert_equal worker_name, @quiet_job.worker_name
      end
    end

    describe '#after_complete' do
      it 'destroy on complete' do
        @quiet_job.destroy_on_complete = true
        @quiet_job.start!
        assert_equal false, @quiet_job.work(@worker)
        assert @quiet_job.completed?, @quiet_job.state
        assert_equal 0, RocketJob::Job.where(id: @quiet_job.id).count
      end
    end

    describe '#fail!' do
      it 'fail with message' do
        @quiet_job.start!
        @quiet_job.fail!('myworker:2323', 'oh no')
        assert_equal true, @quiet_job.failed?
        h = @quiet_job.status
        assert_equal :failed, h['state']
        assert_equal @description, h['description']
        assert_equal 'RocketJob::JobException', h['exception']['class_name'], h
        assert_equal 'oh no', h['exception']['message'], h
      end

      it 'fail with exception' do
        @quiet_job.start!
        exception = nil
        begin
          blah
        rescue Exception => exc
          exception = exc
        end
        @quiet_job.fail!('myworker:2323', exception)
        assert_equal true, @quiet_job.failed?
        h = @quiet_job.status
        assert_equal :failed, h['state']
        assert_equal @description, h['description']
        assert_equal exception.class.name.to_s, h['exception']['class_name'], h
        assert h['exception']['message'].include?('undefined local variable or method'), h
      end
    end

    describe '#retry!' do
      it 'retry failed jobs' do
        worker_name      = 'server:12345'
        @quiet_job.worker_name = worker_name
        @quiet_job.start!
        assert @quiet_job.running?
        assert_equal worker_name, @quiet_job.worker_name

        @quiet_job.fail!(worker_name, 'oh no')
        assert @quiet_job.failed?
        assert_equal 'oh no', @quiet_job.exception.message

        @quiet_job.retry!
        assert @quiet_job.queued?
        assert_equal nil, @quiet_job.worker_name
        assert_equal nil, @quiet_job.exception
      end
    end

  end
end

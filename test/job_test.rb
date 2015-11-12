require_relative 'test_helper'
require_relative 'jobs/test_job'

# Unit Test for RocketJob::Job
class JobTest < Minitest::Test
  describe RocketJob::Job do
    before do
      @description = 'Hello World'
      @quiet_job = Jobs::QuietJob.new(
        description:         @description,
        worker_name:         'worker:123'
      )
      @quiet_job2 = Jobs::QuietJob.new(
        description:         @description,
        worker_name:         'worker:123'
      )
    end

    after do
      @quiet_job.destroy if @quiet_job && !@quiet_job.new_record?
      @quiet_job2.destroy if @quiet_job2 && !@quiet_job2.new_record?
    end

    describe '#status' do
      it 'return status for a queued job' do
        assert_equal true, @quiet_job.queued?
        h = @quiet_job.status
        assert_equal :queued, h['state']
        assert_equal @description, h['description']
      end

      it 'return status for a failed job' do
        @quiet_job.start!
        @quiet_job.fail!('worker:1234', 'oh no')
        assert_equal true, @quiet_job.failed?
        h = @quiet_job.status
        assert_equal :failed, h['state']
        assert_equal @description, h['description']
        assert_equal 'RocketJob::JobException', h['exception']['class_name'], h
        assert_equal 'oh no', h['exception']['message'], h
      end

      it 'mark user as reason for failure when not supplied' do
        @quiet_job.start!
        @quiet_job.fail!
        assert_equal true, @quiet_job.failed?
        assert_equal @description, @quiet_job.description
        assert_equal 'RocketJob::JobException', @quiet_job.exception.class_name
        assert_equal '', @quiet_job.exception.message
        assert_equal '', @quiet_job.exception.worker_name
      end
    end

    describe '.requeue_dead_worker' do
      it 'requeue jobs from dead workers' do
        assert_equal 52, @quiet_job2.priority
        worker_name      = 'server:12345'
        @quiet_job.worker_name = worker_name
        @quiet_job.start!
        assert @quiet_job.running?, @quiet_job.state

        worker_name2      = 'server:76467'
        @quiet_job2.worker_name = worker_name2
        @quiet_job2.start!
        assert_equal true, @quiet_job2.valid?
        assert @quiet_job2.running?, @quiet_job2.state
        @quiet_job2.save!

        RocketJob::Job.requeue_dead_worker(worker_name)
        @quiet_job.reload

        assert @quiet_job.queued?
        assert_equal nil, @quiet_job.worker_name

        assert_equal worker_name2, @quiet_job2.worker_name
        @quiet_job2.reload
        assert_equal worker_name2, @quiet_job2.worker_name
        assert @quiet_job2.running?, @quiet_job2.state
        assert_equal worker_name2, @quiet_job2.worker_name
      end
    end

  end
end

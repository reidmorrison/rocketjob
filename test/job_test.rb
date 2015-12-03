require_relative 'test_helper'

# Unit Test for RocketJob::Job
class JobTest < Minitest::Test

  class SimpleJob < RocketJob::Job
    def perform
    end
  end

  describe RocketJob::Job do
    before do
      @description = 'Hello World'
      @job         = SimpleJob.new(description: @description)
      @job2        = SimpleJob.new(description: @description, priority: 52)
    end

    after do
      @job.destroy if @job && !@job.new_record?
      @job2.destroy if @job2 && !@job2.new_record?
    end

    describe '#status' do
      it 'return status for a queued job' do
        assert_equal true, @job.queued?
        h = @job.status
        assert_equal :queued, h['state']
        assert_equal @description, h['description']
      end

      it 'return status for a failed job' do
        @job.start!
        @job.fail!('worker:1234', 'oh no')
        assert_equal true, @job.failed?
        h = @job.status
        assert_equal :failed, h['state']
        assert_equal @description, h['description']
        assert_equal 'RocketJob::JobException', h['exception']['class_name'], h
        assert_equal 'oh no', h['exception']['message'], h
      end

      it 'mark user as reason for failure when not supplied' do
        @job.start!
        @job.fail!
        assert_equal true, @job.failed?
        assert_equal @description, @job.description
        assert_equal 'RocketJob::JobException', @job.exception.class_name
        assert_equal '', @job.exception.message
        assert_equal '', @job.exception.worker_name
      end
    end

    describe '.requeue_dead_worker' do
      it 'requeue jobs from dead workers' do
        assert_equal 52, @job2.priority
        worker_name      = 'server:12345'
        @job.worker_name = worker_name
        @job.start!
        assert @job.running?, @job.state

        worker_name2      = 'server:76467'
        @job2.worker_name = worker_name2
        @job2.start!
        assert_equal true, @job2.valid?
        assert @job2.running?, @job2.state
        @job2.save!

        RocketJob::Job.requeue_dead_worker(worker_name)
        @job.reload

        assert @job.queued?
        assert_equal nil, @job.worker_name

        assert_equal worker_name2, @job2.worker_name
        @job2.reload
        assert_equal worker_name2, @job2.worker_name
        assert @job2.running?, @job2.state
        assert_equal worker_name2, @job2.worker_name
      end
    end

  end
end

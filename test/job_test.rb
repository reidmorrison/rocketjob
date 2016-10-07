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
    end

    describe '.requeue_dead_server' do
      it 'requeue jobs from dead workers' do
        assert_equal 52, @job2.priority
        server_name      = 'server:12345'
        @job.server_name = server_name
        @job.start!
        assert @job.running?, @job.state

        worker_name2      = 'server:76467'
        @job2.server_name = worker_name2
        @job2.start!
        assert_equal true, @job2.valid?
        assert @job2.running?, @job2.state
        @job2.save!

        RocketJob::Job.requeue_dead_server(server_name)
        @job.reload

        assert @job.queued?
        assert_equal nil, @job.server_name

        assert_equal worker_name2, @job2.server_name
        @job2.reload
        assert_equal worker_name2, @job2.server_name
        assert @job2.running?, @job2.state
        assert_equal worker_name2, @job2.server_name
      end
    end

  end
end

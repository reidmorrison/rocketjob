require_relative 'test_helper'
require_relative 'jobs/test_job'

# Unit Test for RocketJob::Worker
class WorkerTest < Minitest::Test
  context RocketJob::Worker do
    setup do
      RocketJob::Config.instance.heartbeat_seconds = 0.1
      RocketJob::Config.instance.max_poll_seconds  = 0.1

      @worker      = RocketJob::Worker.new
      @description = 'Hello World'
      @arguments   = [1]
      @job         = Jobs::TestJob.new(
        description:         @description,
        arguments:           @arguments,
        destroy_on_complete: false
      )
    end

    teardown do
      @job.destroy if @job && !@job.new_record?
    end

    context '.config' do
      should 'support multiple databases' do
        assert_equal 'test_rocketjob', RocketJob::Job.collection.db.name
      end
    end

    context '#run' do
      should 'run a worker' do
        Thread.new do
          sleep 1
          @worker.stop!
        end
        @worker.run
        assert_equal :stopping, @worker.state, @worker.inspect
      end
    end

  end
end

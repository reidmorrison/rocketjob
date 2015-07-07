require_relative 'test_helper'
require_relative 'jobs/test_job'

# Unit Test for RocketJob::Server
class ServerTest < Minitest::Test
  context RocketJob::Server do
    setup do
      RocketJob::Config.instance.heartbeat_seconds = 0.1
      RocketJob::Config.instance.max_poll_seconds  = 0.1
      @server = RocketJob::Server.new
      @description = 'Hello World'
      @arguments   = [ 1 ]
      @job = Jobs::TestJob.new(
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
        assert_equal 'test_rocket_job', RocketJob::Job.collection.db.name
      end
    end

    context '#run' do
      should 'run a server' do
        Thread.new { sleep 1; @server.stop!}
        @server.run
        assert_equal :stopping, @server.state, @server.inspect
      end
    end

  end
end

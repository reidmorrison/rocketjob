require_relative 'test_helper'
require_relative 'workers/single'

# Unit Test for BatchJob::Server
class ServerTest < Minitest::Test
  context BatchJob::Server do
    setup do
      @server = BatchJob::Server.new
      @description = 'Hello World'
      @arguments   = [ 1 ]
      @job = BatchJob::Single.new(
        description:         @description,
        klass:               'Workers::Single',
        arguments:           @arguments,
        destroy_on_complete: false
      )
    end

    teardown do
      @job.destroy if @job && !@job.new_record?
    end

    context '.config' do
      should 'support multiple databases' do
        assert_equal 'test_batch_job', BatchJob::Single.collection.db.name
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

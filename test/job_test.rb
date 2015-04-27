require_relative 'test_helper'
require_relative 'workers/job'

# Unit Test for RocketJob::Job
class JobTest < Minitest::Test
  context RocketJob::Job do
    setup do
      @server = RocketJob::Server.new
      @server.started
      @description = 'Hello World'
      @arguments   = [ 1 ]
      @job = RocketJob::Job.new(
        description:         @description,
        klass:               'Workers::Job',
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

    context '#save!' do
      should 'save a blank job' do
        @job.save!
        assert_nil   @job.server_name
        assert_nil   @job.completed_at
        assert       @job.created_at
        assert_equal @description, @job.description
        assert_equal false, @job.destroy_on_complete
        assert_nil   @job.expires_at
        assert_equal @arguments, @job.arguments
        assert_equal 0, @job.percent_complete
        assert_equal 50, @job.priority
        assert_equal true, @job.repeatable
        assert_equal 0, @job.failure_count
        assert_nil   @job.run_at
        assert_nil   @job.schedule
        assert_nil   @job.started_at
        assert_equal :queued, @job.state
      end
    end

    context '#status' do
      should 'return status for a queued job' do
        assert_equal true, @job.queued?
        h = @job.status
        assert_equal :queued,      h[:state]
        assert_equal @description, h[:description]
      end
    end

    context '#work' do
      should 'call default perform method' do
        @job.start!
        assert_equal 1, @job.work(@server)
        assert_equal true, @job.completed?
        assert_equal 2,    Workers::Job.result
      end

      should 'call specific method' do
        @job.perform_method = :sum
        @job.arguments = [ 23, 45 ]
        @job.start!
        assert_equal 1, @job.work(@server)
        assert_equal true, @job.completed?
        assert_equal 68,    Workers::Job.result
      end

      should 'destroy on complete' do
        @job.destroy_on_complete = true
        @job.start!
        assert_equal 1, @job.work(@server)
        assert_equal nil, RocketJob::Job.find_by_id(@job.id)
      end

      should 'silence logging when log_level is set' do
        @job.destroy_on_complete = true
        @job.log_level           = :warn
        @job.perform_method      = :noisy_logger
        @job.arguments           = []
        @job.start!
        logged = false
        Workers::Job.logger.stub(:log_internal, -> level, index, message, payload, exception { logged = true if message.include?('some very noisy logging')}) do
          assert_equal 1, @job.work(@server), @job.inspect
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
          Workers::Job.logger.stub(:log_internal, -> { logged = true }) do
            assert_equal 1, @job.work(@server)
          end
        end
        assert_equal false, logged
      end

      should 'call before and after' do
        named_parameters = { 'counter' => 23 }
        @job.perform_method = :event
        @job.arguments = [ named_parameters ]
        @job.start!
        assert_equal 1, @job.work(@server), @job.inspect
        assert_equal true, @job.completed?
        assert_equal named_parameters.merge('before_event' => true, 'after_event' => true), @job.arguments.first
      end

    end

  end
end

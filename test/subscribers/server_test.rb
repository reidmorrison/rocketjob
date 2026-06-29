require_relative "../test_helper"

class ServerSubscriberTest < Minitest::Test
  describe RocketJob::Subscribers::Server do
    let(:server) { RocketJob::Server.create! }
    let(:supervisor) { RocketJob::Supervisor.new(server) }
    let(:subscriber) { RocketJob::Subscribers::Server.new(supervisor) }

    before do
      RocketJob::Server.destroy_all
      reset_supervisor_state
    end

    after do
      RocketJob::Server.destroy_all
      reset_supervisor_state
    end

    # The shutdown / event indicators are class level instance variables shared
    # across the process, so reset them between tests to keep them isolated.
    def reset_supervisor_state
      RocketJob::Supervisor.instance_variable_get(:@shutdown).reset
      RocketJob::Supervisor.instance_variable_get(:@event).reset
    end

    def event_set?
      RocketJob::Supervisor.instance_variable_get(:@event).set?
    end

    describe "#initialize" do
      it "retains the supplied supervisor" do
        assert_equal supervisor, subscriber.supervisor
      end
    end

    describe "#kill" do
      it "shuts down and kills the pool for this server" do
        pool = Minitest::Mock.new
        pool.expect(:stop, nil)
        pool.expect(:living_count, 0)
        pool.expect(:kill, nil)
        supervisor.instance_variable_set(:@worker_pool, pool)

        subscriber.kill

        assert RocketJob::Supervisor.shutdown?
        pool.verify
      end

      it "waits for the pool to terminate when workers are still living" do
        pool = Minitest::Mock.new
        pool.expect(:stop, nil)
        pool.expect(:living_count, 2)
        pool.expect(:kill, nil)
        supervisor.instance_variable_set(:@worker_pool, pool)

        subscriber.kill(wait_timeout: 0.1)

        assert RocketJob::Supervisor.shutdown?
        pool.verify
      end

      it "ignores the request when it is for a different server" do
        pool = Minitest::Mock.new
        supervisor.instance_variable_set(:@worker_pool, pool)

        subscriber.kill(server_id: "000000000000000000000000")

        refute RocketJob::Supervisor.shutdown?
        # No interactions expected with the worker pool.
        pool.verify
      end
    end

    describe "#pause" do
      it "pauses a running server and signals an event" do
        server.started!

        subscriber.pause

        assert server.paused?
        assert event_set?
      end

      it "does not pause a server that cannot be paused but still signals an event" do
        refute server.may_pause?

        subscriber.pause

        assert server.starting?
        assert event_set?
      end

      it "ignores the request when it is for a different server" do
        server.started!

        subscriber.pause(server_id: "000000000000000000000000")

        assert server.running?
        refute event_set?
      end
    end

    describe "#refresh" do
      it "signals an event" do
        subscriber.refresh
        assert event_set?
      end

      it "ignores the request when it is for a different server" do
        subscriber.refresh(name: "someone-else")
        refute event_set?
      end
    end

    describe "#resume" do
      it "resumes a paused server and signals an event" do
        server.started!
        server.pause!
        assert server.paused?

        subscriber.resume

        assert server.running?
        assert event_set?
      end

      it "does not resume a server that cannot be resumed but still signals an event" do
        server.started!
        refute server.may_resume?

        subscriber.resume

        assert server.running?
        assert event_set?
      end
    end

    describe "#stop" do
      it "requests a shutdown" do
        subscriber.stop
        assert RocketJob::Supervisor.shutdown?
      end

      it "ignores the request when it is for a different server" do
        subscriber.stop(server_id: "000000000000000000000000")
        refute RocketJob::Supervisor.shutdown?
      end
    end

    describe "#thread_dump" do
      it "logs the worker backtraces" do
        pool = Minitest::Mock.new
        pool.expect(:log_backtraces, nil)
        supervisor.instance_variable_set(:@worker_pool, pool)

        subscriber.thread_dump

        pool.verify
      end

      it "ignores the request when it is for a different server" do
        pool = Minitest::Mock.new
        supervisor.instance_variable_set(:@worker_pool, pool)

        subscriber.thread_dump(name: "someone-else")

        # No interactions expected with the worker pool.
        pool.verify
      end
    end

    # The private #my_server? predicate decides whether an event applies to this
    # server. Exercise it through #stop, which has no other side effects.
    describe "server targeting" do
      it "acts when neither server_id nor name are supplied" do
        subscriber.stop
        assert RocketJob::Supervisor.shutdown?
      end

      it "acts when the name matches this server" do
        subscriber.stop(name: server.name)
        assert RocketJob::Supervisor.shutdown?
      end

      it "acts when the server_id matches this server" do
        subscriber.stop(server_id: server.id)
        assert RocketJob::Supervisor.shutdown?
      end

      it "ignores a non-matching name" do
        subscriber.stop(name: "someone-else")
        refute RocketJob::Supervisor.shutdown?
      end

      it "ignores a non-matching server_id" do
        subscriber.stop(server_id: "000000000000000000000000")
        refute RocketJob::Supervisor.shutdown?
      end
    end
  end
end

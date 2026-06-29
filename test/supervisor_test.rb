require_relative "test_helper"

class SupervisorTest < Minitest::Test
  describe RocketJob::Supervisor do
    let(:server) { RocketJob::Server.create! }
    let(:supervisor) { RocketJob::Supervisor.new(server) }

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

    describe "#initialize" do
      it "retains the supplied server" do
        assert_equal server, supervisor.server
      end

      it "creates a worker pool for the server" do
        assert_instance_of RocketJob::WorkerPool, supervisor.worker_pool
        assert_equal server.name, supervisor.worker_pool.server_name
      end
    end

    describe "#synchronize" do
      it "yields the supplied block" do
        called = false
        supervisor.synchronize { called = true }
        assert called
      end

      it "returns the value of the block" do
        assert_equal(42, supervisor.synchronize { 42 })
      end
    end

    describe "#stop!" do
      it "stops a running server" do
        server.started!
        assert server.running?

        pool = Minitest::Mock.new
        pool.expect(:stop, nil)
        pool.expect(:join, true)
        supervisor.instance_variable_set(:@worker_pool, pool)

        supervisor.stop!

        assert server.stopping?
        pool.verify
      end

      it "does not stop a server that cannot be stopped" do
        server.started!
        server.stop!
        assert server.stopping?
        refute server.may_stop?

        pool = Minitest::Mock.new
        pool.expect(:stop, nil)
        pool.expect(:join, true)
        supervisor.instance_variable_set(:@worker_pool, pool)

        supervisor.stop!

        assert server.stopping?
        pool.verify
      end

      it "waits and refreshes the server while workers are still running" do
        server.started!

        pool = Minitest::Mock.new
        pool.expect(:stop, nil)
        pool.expect(:join, false)
        pool.expect(:living_count, 2)
        pool.expect(:join, true)
        supervisor.instance_variable_set(:@worker_pool, pool)

        supervisor.stop!

        assert_equal 2, server.reload.heartbeat.workers
        pool.verify
      end
    end

    # Runs the supplied block with the event listener and subscribers stubbed out
    # so that #run does not start real threads or block waiting on MongoDB events.
    def stub_run_environment(&block)
      yielder      = ->(_server, &blk) { blk.call }
      bare_yielder = ->(&blk) { blk.call }
      RocketJob::Event.stub(:listener, nil) do
        RocketJob::Subscribers::Server.stub(:subscribe, yielder) do
          RocketJob::Subscribers::Worker.stub(:subscribe, yielder) do
            RocketJob::Subscribers::Logger.stub(:subscribe, bare_yielder, &block)
          end
        end
      end
    end

    describe "#run" do
      it "starts the server and supervises the pool" do
        supervise_called = false
        stop_called      = false

        stub_run_environment do
          supervisor.stub(:supervise_pool, -> { supervise_called = true }) do
            supervisor.stub(:stop!, -> { stop_called = true }) do
              supervisor.run
            end
          end
        end

        assert supervise_called, "Expected supervise_pool to be invoked"
        assert stop_called, "Expected stop! to be invoked"
        assert server.reload.running?
      end

      it "shuts down gracefully when the server document is destroyed" do
        stub_run_environment do
          raiser = -> { RocketJob::Server.find("000000000000000000000000") }
          supervisor.stub(:supervise_pool, raiser) do
            # Should rescue Mongoid::Errors::DocumentNotFound internally.
            supervisor.run
          end
        end

        assert server.reload.running?
      end

      it "rescues unexpected exceptions" do
        stub_run_environment do
          supervisor.stub(:supervise_pool, -> { raise "boom" }) do
            # Should rescue the exception internally rather than propagating it.
            supervisor.run
          end
        end

        assert server.reload.running?
      end
    end

    describe "#supervise_pool" do
      it "returns immediately when already shutting down" do
        RocketJob::Supervisor.shutdown!

        pool = Minitest::Mock.new
        supervisor.instance_variable_set(:@worker_pool, pool)

        supervisor.supervise_pool

        # No interactions expected with the worker pool.
        pool.verify
      end

      it "prunes and rebalances while the server is running" do
        server.started!

        pool = Minitest::Mock.new
        pool.expect(:prune, 0)
        pool.expect(:rebalance, 0, [server.max_workers, true])
        pool.expect(:living_count, 3)
        supervisor.instance_variable_set(:@worker_pool, pool)

        RocketJob::Supervisor.stub(:wait_for_event, ->(_timeout) { RocketJob::Supervisor.shutdown! }) do
          supervisor.supervise_pool
        end

        assert_equal 3, server.reload.heartbeat.workers
        pool.verify
      end

      it "stops the pool while the server is paused" do
        server.started!
        server.pause!
        assert server.paused?

        pool = Minitest::Mock.new
        pool.expect(:stop, nil)
        pool.expect(:prune, 0)
        pool.expect(:living_count, 0)
        supervisor.instance_variable_set(:@worker_pool, pool)

        RocketJob::Supervisor.stub(:wait_for_event, ->(_timeout) { RocketJob::Supervisor.shutdown! }) do
          supervisor.supervise_pool
        end

        pool.verify
      end

      it "refreshes the heartbeat when the server is neither running nor paused" do
        server.started!
        server.stop!
        assert server.stopping?

        pool = Minitest::Mock.new
        pool.expect(:living_count, 0)
        supervisor.instance_variable_set(:@worker_pool, pool)

        RocketJob::Supervisor.stub(:wait_for_event, ->(_timeout) { RocketJob::Supervisor.shutdown! }) do
          supervisor.supervise_pool
        end

        pool.verify
      end
    end

    describe ".shutdown?" do
      it "is false until a shutdown is requested" do
        refute RocketJob::Supervisor.shutdown?
      end

      it "is true once a shutdown is requested" do
        RocketJob::Supervisor.shutdown!
        assert RocketJob::Supervisor.shutdown?
      end
    end

    describe ".shutdown!" do
      it "sets the shutdown indicator and signals an event" do
        RocketJob::Supervisor.shutdown!
        assert RocketJob::Supervisor.shutdown?
        assert RocketJob::Supervisor.instance_variable_get(:@event).set?
      end
    end

    describe ".event!" do
      it "signals a pending event without requesting shutdown" do
        RocketJob::Supervisor.event!
        assert RocketJob::Supervisor.instance_variable_get(:@event).set?
        refute RocketJob::Supervisor.shutdown?
      end
    end

    describe ".wait_for_event" do
      it "returns immediately when an event is already set" do
        RocketJob::Supervisor.event!
        elapsed = time_block { RocketJob::Supervisor.wait_for_event(5) }
        assert elapsed < 1, "Expected to return immediately, took #{elapsed}s"
      end

      it "resets the event after waiting" do
        RocketJob::Supervisor.event!
        RocketJob::Supervisor.wait_for_event(1)
        refute RocketJob::Supervisor.instance_variable_get(:@event).set?
      end

      it "waits for the timeout when no event is set" do
        elapsed = time_block { RocketJob::Supervisor.wait_for_event(0.2) }
        assert elapsed >= 0.2, "Expected to wait for the timeout, took #{elapsed}s"
      end
    end

    describe ".register_signal_handlers" do
      it "installs handlers that request a shutdown" do
        handlers = {}
        Signal.stub(:trap, ->(signal, &block) { handlers[signal] = block }) do
          RocketJob::Supervisor.send(:register_signal_handlers)
        end

        assert handlers["SIGTERM"], "Expected a SIGTERM handler"
        assert handlers["INT"], "Expected an INT handler"

        handlers.each_value do |handler|
          RocketJob::Supervisor.instance_variable_get(:@shutdown).reset
          handler.call
          # The handler requests the shutdown from a separate thread.
          50.times do
            break if RocketJob::Supervisor.shutdown?

            sleep(0.01)
          end
          assert RocketJob::Supervisor.shutdown?, "Expected the handler to request a shutdown"
        end
      end

      it "warns rather than raising when handlers cannot be installed" do
        Signal.stub(:trap, ->(*) { raise "cannot trap" }) do
          # Should rescue the error internally rather than propagating it.
          RocketJob::Supervisor.send(:register_signal_handlers)
        end
        pass
      end
    end

    def time_block
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    end
  end
end

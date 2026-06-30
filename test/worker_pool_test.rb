require_relative "test_helper"

# Require Supervisor explicitly so it is fully loaded before WorkerPool, which
# requires rocket_job/supervisor/shutdown and would otherwise trigger a
# circular autoload of Supervisor when this file is run on its own.
require "rocket_job/supervisor"

class WorkerPoolTest < Minitest::Test
  # A lightweight stand-in for ThreadWorker that records the calls made to it
  # without starting a real operating system thread.
  class FakeWorker
    attr_reader :id, :server_name, :thread
    attr_writer :alive

    def initialize(id:, server_name:, alive: true)
      @id          = id
      @server_name = server_name
      @alive       = alive
      @thread      = Object.new
      @shutdown    = false
      @killed      = false
    end

    def alive?
      @alive
    end

    def shutdown!
      @shutdown = true
    end

    def shutdown?
      @shutdown
    end

    def kill
      @killed = true
    end

    def killed?
      @killed
    end

    # Mirrors ThreadWorker#join, which returns truthy once the thread has stopped.
    def join(_timeout = nil)
      !@alive
    end
  end

  describe RocketJob::WorkerPool do
    let(:server_name) { "test_server:1234" }
    let(:pool) { RocketJob::WorkerPool.new(server_name) }

    before do
      reset_supervisor_state
    end

    after do
      reset_supervisor_state
    end

    def reset_supervisor_state
      RocketJob::Supervisor.instance_variable_get(:@shutdown).reset
      RocketJob::Supervisor.instance_variable_get(:@event).reset
    end

    # Stub ThreadWorker.new so rebalance/add_one builds FakeWorker instances.
    def stub_thread_worker(&block)
      builder = lambda do |id:, server_name:|
        FakeWorker.new(id: id, server_name: server_name)
      end
      RocketJob::ThreadWorker.stub(:new, builder, &block)
    end

    describe "#initialize" do
      it "retains the server name" do
        assert_equal server_name, pool.server_name
      end

      it "starts with no workers" do
        assert_empty pool.workers
      end
    end

    describe "#find" do
      it "returns the worker with the matching id" do
        worker = FakeWorker.new(id: 7, server_name: server_name)
        pool.workers << worker

        assert_equal worker, pool.find(7)
      end

      it "returns nil when no worker matches" do
        pool.workers << FakeWorker.new(id: 1, server_name: server_name)

        assert_nil pool.find(99)
      end
    end

    describe "#rebalance" do
      it "starts workers up to max_workers" do
        stub_thread_worker do
          pool.rebalance(3)
        end

        assert_equal 3, pool.workers.count
        assert_equal [1, 2, 3], pool.workers.map(&:id)
        assert(pool.workers.all? { |w| w.server_name == server_name })
      end

      it "returns 0 when already at max_workers" do
        3.times { |i| pool.workers << FakeWorker.new(id: i, server_name: server_name) }

        stub_thread_worker do
          assert_equal 0, pool.rebalance(3)
        end
        assert_equal 3, pool.workers.count
      end

      it "only starts enough workers to reach max_workers" do
        pool.workers << FakeWorker.new(id: 1, server_name: server_name)
        stub_thread_worker do
          pool.rebalance(3)
        end

        assert_equal 3, pool.workers.count
      end

      it "does not count dead workers towards the living total" do
        pool.workers << FakeWorker.new(id: 1, server_name: server_name, alive: false)
        stub_thread_worker do
          pool.rebalance(2)
        end
        # The dead worker remains, plus two freshly started workers.
        assert_equal 3, pool.workers.count
        assert_equal 2, pool.living_count
      end

      it "returns -1 and stops adding workers when a shutdown is requested" do
        stub_thread_worker do
          RocketJob::Supervisor.shutdown!

          assert_equal(-1, pool.rebalance(5, true))
        end
        # The first worker is always added before the shutdown check.
        assert_equal 1, pool.workers.count
      end
    end

    describe "#prune" do
      it "returns 0 when all workers are alive" do
        2.times { |i| pool.workers << FakeWorker.new(id: i, server_name: server_name) }

        assert_equal 0, pool.prune
        assert_equal 2, pool.workers.count
      end

      it "removes dead workers and returns the number removed" do
        pool.workers << FakeWorker.new(id: 1, server_name: server_name, alive: true)
        pool.workers << FakeWorker.new(id: 2, server_name: server_name, alive: false)
        pool.workers << FakeWorker.new(id: 3, server_name: server_name, alive: false)

        assert_equal 2, pool.prune
        assert_equal [1], pool.workers.map(&:id)
      end
    end

    describe "#stop" do
      it "tells every worker to shut down" do
        workers = Array.new(3) { |i| FakeWorker.new(id: i, server_name: server_name) }
        workers.each { |w| pool.workers << w }

        pool.stop

        assert(workers.all?(&:shutdown?))
      end
    end

    describe "#kill" do
      it "kills every worker and clears the pool" do
        workers = Array.new(3) { |i| FakeWorker.new(id: i, server_name: server_name) }
        workers.each { |w| pool.workers << w }

        pool.kill

        assert(workers.all?(&:killed?))
        assert_empty pool.workers
      end
    end

    describe "#join" do
      it "returns true once all workers have stopped" do
        pool.workers << FakeWorker.new(id: 1, server_name: server_name, alive: false)
        pool.workers << FakeWorker.new(id: 2, server_name: server_name, alive: false)

        assert pool.join(0.01)
        assert_empty pool.workers
      end

      it "returns false when a worker does not stop within the timeout" do
        pool.workers << FakeWorker.new(id: 1, server_name: server_name, alive: true)

        refute pool.join(0.01)
        # The still-running worker remains in the pool.
        assert_equal 1, pool.workers.count
      end
    end

    describe "#living_count" do
      it "counts only the workers that are alive" do
        pool.workers << FakeWorker.new(id: 1, server_name: server_name, alive: true)
        pool.workers << FakeWorker.new(id: 2, server_name: server_name, alive: false)
        pool.workers << FakeWorker.new(id: 3, server_name: server_name, alive: true)

        assert_equal 2, pool.living_count
      end
    end
  end
end

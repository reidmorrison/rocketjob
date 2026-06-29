require_relative "../test_helper"

class WorkerSubscriberTest < Minitest::Test
  describe RocketJob::Subscribers::Worker do
    let(:server) { RocketJob::Server.create! }
    let(:supervisor) { RocketJob::Supervisor.new(server) }
    let(:subscriber) { RocketJob::Subscribers::Worker.new(supervisor) }
    let(:worker_id) { 1 }
    let(:other_server_id) { "000000000000000000000000" }

    before do
      RocketJob::Server.destroy_all
    end

    after do
      RocketJob::Server.destroy_all
    end

    # Minimal stand-in for a RocketJob::Worker that records the lifecycle calls
    # the subscriber makes against it.
    class FakeWorker
      attr_reader :calls, :thread

      def initialize(alive: true, thread: nil)
        @alive  = alive
        @thread = thread
        @calls  = []
      end

      def alive?
        @alive
      end

      def shutdown!
        @calls << :shutdown!
      end

      def join(timeout)
        @calls << [:join, timeout]
      end

      def kill
        @calls << :kill
      end
    end

    # Stand-in for the WorkerPool that returns a preconfigured worker by id.
    class FakePool
      attr_reader :requested_ids

      def initialize(worker)
        @worker        = worker
        @requested_ids = []
      end

      def find(id)
        @requested_ids << id
        @worker
      end
    end

    def stub_pool(worker)
      pool = FakePool.new(worker)
      supervisor.instance_variable_set(:@worker_pool, pool)
      pool
    end

    describe "#initialize" do
      it "retains the supplied supervisor" do
        assert_equal supervisor, subscriber.supervisor
      end
    end

    describe "#kill" do
      it "shuts down, joins, and kills the located worker" do
        worker = FakeWorker.new
        stub_pool(worker)

        subscriber.kill(server_id: server.id, worker_id: worker_id, wait_timeout: 0.1)

        assert_equal [:shutdown!, [:join, 0.1], :kill], worker.calls
      end

      it "defaults the wait_timeout when not supplied" do
        worker = FakeWorker.new
        stub_pool(worker)

        subscriber.kill(server_id: server.id, worker_id: worker_id)

        assert_equal [:shutdown!, [:join, 3], :kill], worker.calls
      end

      it "ignores the request when it is for a different server" do
        worker = FakeWorker.new
        pool   = stub_pool(worker)

        subscriber.kill(server_id: other_server_id, worker_id: worker_id)

        assert_empty worker.calls
        assert_empty pool.requested_ids
      end

      it "does nothing when the worker cannot be located" do
        pool = stub_pool(nil)

        subscriber.kill(server_id: server.id, worker_id: worker_id)

        assert_equal [worker_id], pool.requested_ids
      end

      it "does nothing when the located worker is not alive" do
        worker = FakeWorker.new(alive: false)
        stub_pool(worker)

        subscriber.kill(server_id: server.id, worker_id: worker_id)

        assert_empty worker.calls
      end

      it "does nothing when no worker_id is supplied" do
        worker = FakeWorker.new
        pool   = stub_pool(worker)

        subscriber.kill(server_id: server.id, worker_id: nil)

        assert_empty worker.calls
        assert_empty pool.requested_ids
      end
    end

    describe "#stop" do
      it "shuts down the located worker" do
        worker = FakeWorker.new
        stub_pool(worker)

        subscriber.stop(server_id: server.id, worker_id: worker_id)

        assert_equal [:shutdown!], worker.calls
      end

      it "ignores the request when it is for a different server" do
        worker = FakeWorker.new
        pool   = stub_pool(worker)

        subscriber.stop(server_id: other_server_id, worker_id: worker_id)

        assert_empty worker.calls
        assert_empty pool.requested_ids
      end

      it "does nothing when the worker cannot be located" do
        stub_pool(nil)

        # Nothing to assert other than that no error is raised.
        subscriber.stop(server_id: server.id, worker_id: worker_id)
      end

      it "does nothing when the located worker is not alive" do
        worker = FakeWorker.new(alive: false)
        stub_pool(worker)

        subscriber.stop(server_id: server.id, worker_id: worker_id)

        assert_empty worker.calls
      end
    end

    describe "#thread_dump" do
      it "logs the worker backtrace when it has a live thread" do
        worker = FakeWorker.new(thread: Thread.current)
        stub_pool(worker)

        called = false
        subscriber.logger.stub(:backtrace, ->(*) { called = true }) do
          subscriber.thread_dump(server_id: server.id, worker_id: worker_id)
        end

        assert called, "expected the worker backtrace to be logged"
      end

      it "does not log a backtrace when the worker has no thread" do
        worker = FakeWorker.new(thread: nil)
        stub_pool(worker)

        called = false
        subscriber.logger.stub(:backtrace, ->(*) { called = true }) do
          subscriber.thread_dump(server_id: server.id, worker_id: worker_id)
        end

        refute called, "expected no backtrace to be logged without a thread"
      end

      it "ignores the request when it is for a different server" do
        worker = FakeWorker.new(thread: Thread.current)
        pool   = stub_pool(worker)

        called = false
        subscriber.logger.stub(:backtrace, ->(*) { called = true }) do
          subscriber.thread_dump(server_id: other_server_id, worker_id: worker_id)
        end

        refute called
        assert_empty pool.requested_ids
      end

      it "does nothing when the worker cannot be located" do
        stub_pool(nil)

        called = false
        subscriber.logger.stub(:backtrace, ->(*) { called = true }) do
          subscriber.thread_dump(server_id: server.id, worker_id: worker_id)
        end

        refute called
      end
    end
  end
end

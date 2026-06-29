require_relative "test_helper"

class ThreadWorkerTest < Minitest::Test
  describe RocketJob::ThreadWorker do
    before do
      # Ensure the worker thread has no jobs to pick up while running.
      RocketJob::Job.destroy_all
    end

    after do
      RocketJob::Job.destroy_all
    end

    def new_worker
      RocketJob::ThreadWorker.new(id: 1, server_name: "test:1")
    end

    it "starts a live worker thread" do
      worker = new_worker
      assert worker.alive?
      refute worker.shutdown?
    ensure
      worker.shutdown!
      worker.join(5)
    end

    it "shuts down cleanly when requested" do
      worker = new_worker
      worker.shutdown!
      assert worker.shutdown?
      assert worker.join(5), "Expected the worker thread to stop"
      refute worker.alive?
    end

    it "exposes the running thread backtrace" do
      worker = new_worker
      assert_kind_of Array, worker.backtrace
    ensure
      worker.shutdown!
      worker.join(5)
    end

    it "can be killed" do
      worker = new_worker
      # Allow the thread to enter #run so the Shutdown exception is handled there.
      sleep(0.2)
      worker.kill
      assert worker.join(5), "Expected the killed worker thread to stop"
      refute worker.alive?
    end
  end
end

require_relative "test_helper"

class ActiveWorkerTest < Minitest::Test
  class SimpleJob < RocketJob::Job
    def perform
    end
  end

  class SlicedJob < RocketJob::Job
    include RocketJob::Batch

    def perform(record)
      record
    end
  end

  describe RocketJob::ActiveWorker do
    before do
      RocketJob::Job.delete_all
      RocketJob::Server.delete_all
    end

    after do
      RocketJob::Job.delete_all
      RocketJob::Server.delete_all
    end

    def running_job(worker_name)
      SimpleJob.create!(state: :running, started_at: Time.now, worker_name: worker_name)
    end

    describe "#server_name" do
      it "is the worker name without its worker id" do
        assert_equal "host:1234", RocketJob::ActiveWorker.new("host:1234:3", Time.now, nil).server_name
      end

      it "is a server name without a colon" do
        assert_equal "worker1", RocketJob::ActiveWorker.new("worker1:3", Time.now, nil).server_name
      end
    end

    describe ".all" do
      it "returns the workers on the named server only" do
        mine = running_job("host:12:1")
        running_job("host:123:1")

        active_workers = RocketJob::ActiveWorker.all("host:12")

        assert_equal([mine.id], active_workers.collect { |active_worker| active_worker.job.id })
      end

      it "returns the workers processing the slices of a batch job on the named server only" do
        job = SlicedJob.create!(state: :running, sub_state: :processing, worker_name: "host:123:9", started_at: Time.now)
        %w[host:12:1 host:123:5].each do |worker_name|
          slice = job.input.new(records: %w[a], worker_name: worker_name)
          slice.start
          job.input << slice
        end

        assert_equal %w[host:12:1], RocketJob::ActiveWorker.all("host:12").collect(&:name)
        assert_equal %w[host:123:5], RocketJob::ActiveWorker.all("host:123").collect(&:name)
      ensure
        job&.cleanup!
      end

      it "returns the workers on every server" do
        running_job("host:12:1")
        running_job("host:123:1")

        assert_equal %w[host:12:1 host:123:1].sort, RocketJob::ActiveWorker.all.collect(&:name).sort
      end
    end

    describe ".requeue_zombies" do
      it "requeues the jobs of a server that is gone" do
        job = running_job("gone:1:1")

        RocketJob::ActiveWorker.requeue_zombies

        assert_predicate job.reload, :queued?
      end

      it "does not requeue the jobs of a running server whose name has no colon" do
        RocketJob::Server.create!(name: "worker1")
        job = running_job("worker1:3")

        RocketJob::ActiveWorker.requeue_zombies

        assert_predicate job.reload, :running?
      end
    end
  end
end

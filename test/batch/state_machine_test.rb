require_relative "../test_helper"

module Batch
  class StateMachineTest < Minitest::Test
    class SimpleJob < RocketJob::Job
      include RocketJob::Batch

      output_category nils: true

      def perform(record)
        record
      end
    end

    describe RocketJob::Batch::StateMachine do
      before do
        RocketJob::Job.delete_all
        @worker_name  = "server:743934"
        @worker_name2 = "server2:2435"

        @job = SimpleJob.new(
          description:         @description,
          destroy_on_complete: false,
          worker_name:         @worker_name
        )
      end

      after do
        @job.destroy if @job&.persisted?
        @job2.destroy if @job2&.persisted?
      end

      describe "#retry!" do
        it "with substate :before" do
          assert_equal [:main], @job.output_categories.collect(&:name)
          assert_equal [:main], @job.input_categories.collect(&:name)

          @job.start!

          assert_predicate @job, :running?
          assert_equal @worker_name, @job.worker_name
          assert_equal :before, @job.sub_state

          @job.fail!(@worker_name, "oh no")

          assert_predicate @job, :failed?
          assert_equal @worker_name, @job.exception.worker_name

          @job.retry!

          assert_predicate @job, :queued?, @job.state
          assert_nil @job.worker_name
          assert_nil @job.sub_state
        end

        it "with substate :after" do
          @job.start!

          assert_predicate @job, :running?
          assert_equal @worker_name, @job.worker_name
          assert_equal :before, @job.sub_state

          @job.sub_state = :after
          @job.fail!(@worker_name, "oh no")

          assert_predicate @job, :failed?
          assert_equal @worker_name, @job.exception.worker_name

          @job.retry!

          assert_predicate @job, :running?
          assert_nil @job.worker_name
          assert_equal :processing, @job.sub_state
        end

        it "not affect parent class" do
          @job.start!

          assert_predicate @job, :running?
          assert_equal @worker_name, @job.worker_name

          @job.fail!(@worker_name, "oh no")

          assert_predicate @job, :failed?
          assert_equal @worker_name, @job.exception.worker_name

          @job.retry!

          assert_predicate @job, :queued?
          assert_nil @job.worker_name
        end
      end

      describe "#requeue" do
        it "with substate :before" do
          @job.start!

          assert_predicate @job, :running?
          assert_equal @worker_name, @job.worker_name
          assert_equal :before, @job.sub_state

          @job.requeue(@worker_name)

          assert_predicate @job, :queued?
          assert_nil @job.worker_name
        end

        it "with substate :processing" do
          @job.upload_slice([1, 2, 3, 4, 5])
          @job.upload_slice([6, 7, 8, 9, 10])
          @job.start!

          assert_predicate @job, :running?
          assert_equal @worker_name, @job.worker_name
          assert_equal :before, @job.sub_state
          assert_equal 2, @job.input.count, -> { @job.input.to_a.ai }

          @job.sub_state = :processing
          @job.save!
          slice1 = @job.input.next_slice(@worker_name)

          assert_equal @worker_name, slice1.worker_name
          assert_predicate slice1, :running?

          slice2 = @job.input.last

          assert_nil slice2.worker_name
          assert_predicate slice2, :queued?

          @job.requeue!(@worker_name)

          assert_predicate @job, :running?, @job.state
          assert_nil @job.worker_name

          slice1 = @job.input.first

          assert_nil slice1.worker_name
          assert_predicate slice1, :queued?

          slice2 = @job.input.last

          assert_nil slice2.worker_name
          assert_predicate slice2, :queued?
        end

        it "with substate :after" do
          @job.start!

          assert_predicate @job, :running?
          assert_equal @worker_name, @job.worker_name
          assert_equal :before, @job.sub_state

          @job.sub_state = :after

          @job.requeue!(@worker_name)

          assert_predicate @job, :running?
          assert_nil @job.worker_name
        end
      end

      describe ".requeue_dead_server" do
        before do
          @job2 = SimpleJob.new(
            description:         @description,
            destroy_on_complete: false,
            worker_name:         @worker_name2
          )
        end

        it "with substate :before" do
          @job.start!

          assert_predicate @job, :running?
          assert_equal @worker_name, @job.worker_name
          assert_equal :before, @job.sub_state

          @job2.start!

          assert_predicate @job2, :running?
          assert_equal @worker_name2, @job2.worker_name
          assert_equal :before, @job2.sub_state

          RocketJob::Job.requeue_dead_server(@worker_name)

          assert_predicate @job.reload, :queued?, @job.state
          assert_nil @job.worker_name

          assert_predicate @job2.reload, :running?, "Job2 on another worker must not be affected"
          assert_equal @worker_name2, @job2.worker_name
          assert_equal :before, @job2.sub_state
        end

        it "with substate :processing" do
          @job.upload_slice([1, 2, 3, 4, 5])
          @job.upload_slice([6, 7, 8, 9, 10])
          @job.start!

          assert_predicate @job, :running?
          assert_equal @worker_name, @job.worker_name
          assert_equal :before, @job.sub_state
          assert_equal 2, @job.input.count, -> { @job.input.to_a.ai }
          @job.sub_state = :processing
          @job.save!

          @job2.start
          @job2.sub_state = :processing
          @job2.save!

          assert_predicate @job2.reload, :running?
          assert_equal @worker_name2, @job2.worker_name
          assert_equal :processing, @job2.sub_state

          slice1 = @job.input.next_slice(@worker_name)

          assert_equal @worker_name, slice1.worker_name
          assert_predicate slice1, :running?

          slice2 = @job.input.last

          assert_nil slice2.worker_name
          assert_predicate slice2, :queued?

          RocketJob::Job.requeue_dead_server(@worker_name)

          assert_predicate @job.reload, :running?, @job.state
          assert_nil @job.worker_name, -> { @job.ai }

          slice1 = @job.input.first

          assert_nil slice1.worker_name
          assert_predicate slice1, :queued?

          slice2 = @job.input.last

          assert_nil slice2.worker_name
          assert_predicate slice2, :queued?

          assert_predicate @job2.reload, :running?, "Job2 on another worker must not be affected"
          assert_equal :processing, @job2.sub_state
        end

        it "with substate :processing requeues slices by slice owner, not the job worker_name" do
          # Workers join a running batch job read-only (see Worker#find_and_assign_job),
          # so the job's worker_name stays as the worker that entered :processing and
          # does not track the servers currently claiming slices. Recovery of a dead
          # server's in-flight slices must therefore key off the per-slice worker_name.
          live_server = "live_server:222"
          dead_server = "dead_server:333"

          @job.upload_slice([1, 2, 3])
          @job.upload_slice([4, 5, 6])
          @job.start!
          @job.sub_state = :processing
          @job.save!

          live_slice = @job.input.next_slice(live_server)
          dead_slice = @job.input.next_slice(dead_server)

          assert_equal live_server, live_slice.worker_name
          assert_equal dead_server, dead_slice.worker_name

          # The job document points at neither slice owner.
          refute_equal live_server, @job.worker_name
          refute_equal dead_server, @job.worker_name

          RocketJob::Job.requeue_dead_server(dead_server)

          assert_predicate @job.reload, :running?, @job.state
          assert_equal :processing, @job.sub_state
          assert_nil @job.worker_name

          # The dead server's slice is requeued for another worker to pick up.
          dead_slice = @job.input.find(dead_slice.id)

          assert_predicate dead_slice, :queued?
          assert_nil dead_slice.worker_name

          # The live server's slice is untouched and keeps processing.
          live_slice = @job.input.find(live_slice.id)

          assert_predicate live_slice, :running?
          assert_equal live_server, live_slice.worker_name
        end

        it "with substate :after" do
          @job.start!

          assert_predicate @job, :running?
          assert_equal @worker_name, @job.worker_name
          assert_equal :before, @job.sub_state
          @job.sub_state = :after
          @job.save!

          @job2.start
          @job2.sub_state = :after
          @job2.save!

          assert_predicate @job2.reload, :running?
          assert_equal @worker_name2, @job2.worker_name
          assert_equal :after, @job2.sub_state

          RocketJob::Job.requeue_dead_server(@worker_name)

          assert_predicate @job.reload, :running?
          assert_nil @job.worker_name

          assert_predicate @job2.reload, :running?, "Job2 on another worker must not be affected"
          assert_equal @worker_name2, @job2.worker_name
          assert_equal :after, @job2.sub_state
        end
      end
    end
  end
end

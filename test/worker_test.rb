require_relative 'test_helper'
require_relative 'jobs/test_job'

# Unit Test for RocketJob::Worker
class WorkerTest < Minitest::Test
  describe RocketJob::Worker do
    before do
      RocketJob::Config.instance.heartbeat_seconds = 0.1
      RocketJob::Config.instance.max_poll_seconds  = 0.1

      @worker      = RocketJob::Worker.new
      @description = 'Hello World'
      @arguments   = [1]
      @job         = Jobs::TestJob.new(
        description:         @description,
        arguments:           @arguments,
        destroy_on_complete: false
      )
    end

    after do
      @job.destroy if @job && !@job.new_record?
      @worker.destroy if @worker && !@worker.new_record?
    end

    describe '.config' do
      it 'support multiple databases' do
        assert_equal 'test_rocketjob', RocketJob::Job.collection.db.name
      end
    end

    describe '#run' do
      it 'run a worker' do
        Thread.new do
          sleep 1
          @worker.stop!
        end
        @worker.run
        assert_equal :stopping, @worker.state, @worker.inspect
      end
    end

    describe '#zombie?' do
      before do
        RocketJob::Config.instance.heartbeat_seconds = 1
      end

      it 'when not a zombie' do
        @worker.build_heartbeat(
          updated_at:      2.seconds.ago,
          current_threads: 3
        )
        @worker.started!
        assert_equal false, @worker.zombie?
        assert_equal false, @worker.zombie?(4)
        assert_equal true, @worker.zombie?(1)
      end

      it 'when a zombie' do
        @worker.build_heartbeat(
          updated_at:      1.hour.ago,
          current_threads: 5
        )
        @worker.started!
        assert_equal true, @worker.zombie?
      end
    end

    describe '.destroy_zombies' do
      before do
        RocketJob::Config.instance.heartbeat_seconds = 1
      end

      it 'when not a zombie' do
        @worker.build_heartbeat(
          updated_at:      2.seconds.ago,
          current_threads: 3
        )
        @worker.started!
        assert_equal 0, RocketJob::Worker.destroy_zombies
        assert_equal true, RocketJob::Worker.where(id: @worker.id).exist?
      end

      it 'when a zombie' do
        @worker.build_heartbeat(
          updated_at:      10.seconds.ago,
          current_threads: 3
        )
        @worker.started!
        assert_equal 1, RocketJob::Worker.destroy_zombies
        assert_equal false, RocketJob::Worker.where(id: @worker.id).exist?
      end

    end

  end
end

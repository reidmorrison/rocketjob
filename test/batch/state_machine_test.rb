require_relative '../test_helper'

module Plugins
  module Batch
    class StateMachineTest < Minitest::Test
      class SimpleJob < RocketJob::Job
        include RocketJob::Batch

        def perform(record)
          record
        end
      end

      describe RocketJob::Batch::StateMachine do
        before do
          RocketJob::Job.delete_all
          @worker_name  = 'server:743934'
          @worker_name2 = 'server2:2435'

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

        describe '#retry!' do
          it 'with substate :before' do
            assert_equal [:main], @job.output_categories
            assert_equal [:main], @job.input_categories

            @job.start!
            assert @job.running?
            assert_equal @worker_name, @job.worker_name
            assert_equal :before, @job.sub_state

            @job.fail!(@worker_name, 'oh no')
            assert @job.failed?
            assert_equal @worker_name, @job.exception.worker_name

            @job.retry!
            assert @job.queued?, @job.state
            assert_nil @job.worker_name
            assert_nil @job.sub_state
          end

          it 'with substate :after' do
            @job.start!
            assert @job.running?
            assert_equal @worker_name, @job.worker_name
            assert_equal :before, @job.sub_state

            @job.sub_state = :after
            @job.fail!(@worker_name, 'oh no')
            assert @job.failed?
            assert_equal @worker_name, @job.exception.worker_name

            @job.retry!
            assert @job.running?
            assert_nil @job.worker_name
            assert_equal :processing, @job.sub_state
          end

          it 'not affect parent class' do
            @job.start!
            assert @job.running?
            assert_equal @worker_name, @job.worker_name

            @job.fail!(@worker_name, 'oh no')
            assert @job.failed?
            assert_equal @worker_name, @job.exception.worker_name

            @job.retry!
            assert @job.queued?
            assert_nil @job.worker_name
          end
        end

        describe '#requeue' do
          it 'with substate :before' do
            @job.start!
            assert @job.running?
            assert_equal @worker_name, @job.worker_name
            assert_equal :before, @job.sub_state

            @job.requeue(@worker_name)
            assert @job.queued?
            assert_nil @job.worker_name
          end

          it 'with substate :processing' do
            @job.upload_slice([1, 2, 3, 4, 5])
            @job.upload_slice([6, 7, 8, 9, 10])
            @job.start!
            assert @job.running?
            assert_equal @worker_name, @job.worker_name
            assert_equal :before, @job.sub_state
            assert_equal 2, @job.input.count, -> { @job.input.to_a.ai }

            @job.sub_state = :processing
            @job.save!
            slice1 = @job.input.next_slice(@worker_name)
            assert_equal @worker_name, slice1.worker_name
            assert slice1.running?

            slice2 = @job.input.last
            assert_nil slice2.worker_name
            assert slice2.queued?

            @job.requeue!(@worker_name)
            assert @job.running?, @job.state
            assert_nil @job.worker_name

            slice1 = @job.input.first
            assert_nil slice1.worker_name
            assert slice1.queued?

            slice2 = @job.input.last
            assert_nil slice2.worker_name
            assert slice2.queued?
          end

          it 'with substate :after' do
            @job.start!
            assert @job.running?
            assert_equal @worker_name, @job.worker_name
            assert_equal :before, @job.sub_state

            @job.sub_state = :after

            @job.requeue!(@worker_name)
            assert @job.running?
            assert_nil @job.worker_name
          end
        end

        describe '.requeue_dead_server' do
          before do
            @job2 = SimpleJob.new(
              description:         @description,
              destroy_on_complete: false,
              worker_name:         @worker_name2
            )
          end

          it 'with substate :before' do
            @job.start!
            assert @job.running?
            assert_equal @worker_name, @job.worker_name
            assert_equal :before, @job.sub_state

            @job2.start!
            assert @job2.running?
            assert_equal @worker_name2, @job2.worker_name
            assert_equal :before, @job2.sub_state

            RocketJob::Job.requeue_dead_server(@worker_name)
            assert @job.reload.queued?, @job.state
            assert_nil @job.worker_name

            assert @job2.reload.running?, 'Job2 on another worker must not be affected'
            assert_equal @worker_name2, @job2.worker_name
            assert_equal :before, @job2.sub_state
          end

          it 'with substate :processing' do
            @job.upload_slice([1, 2, 3, 4, 5])
            @job.upload_slice([6, 7, 8, 9, 10])
            @job.start!
            assert @job.running?
            assert_equal @worker_name, @job.worker_name
            assert_equal :before, @job.sub_state
            assert_equal 2, @job.input.count, -> { @job.input.to_a.ai }
            @job.sub_state = :processing
            @job.save!

            @job2.start
            @job2.sub_state = :processing
            @job2.save!
            assert @job2.reload.running?
            assert_equal @worker_name2, @job2.worker_name
            assert_equal :processing, @job2.sub_state

            slice1 = @job.input.next_slice(@worker_name)
            assert_equal @worker_name, slice1.worker_name
            assert slice1.running?

            slice2 = @job.input.last
            assert_nil slice2.worker_name
            assert slice2.queued?

            RocketJob::Job.requeue_dead_server(@worker_name)
            assert @job.reload.running?, @job.state
            assert_nil @job.worker_name, -> { @job.ai }

            slice1 = @job.input.first
            assert_nil slice1.worker_name
            assert slice1.queued?

            slice2 = @job.input.last
            assert_nil slice2.worker_name
            assert slice2.queued?

            assert @job2.reload.running?, 'Job2 on another worker must not be affected'
            assert_equal :processing, @job2.sub_state
          end

          it 'with substate :after' do
            @job.start!
            assert @job.running?
            assert_equal @worker_name, @job.worker_name
            assert_equal :before, @job.sub_state
            @job.sub_state = :after
            @job.save!

            @job2.start
            @job2.sub_state = :after
            @job2.save!
            assert @job2.reload.running?
            assert_equal @worker_name2, @job2.worker_name
            assert_equal :after, @job2.sub_state

            RocketJob::Job.requeue_dead_server(@worker_name)
            assert @job.reload.running?
            assert_nil @job.worker_name

            assert @job2.reload.running?, 'Job2 on another worker must not be affected'
            assert_equal @worker_name2, @job2.worker_name
            assert_equal :after, @job2.sub_state
          end
        end
      end
    end
  end
end

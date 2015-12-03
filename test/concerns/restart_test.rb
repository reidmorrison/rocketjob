require_relative '../test_helper'

# Unit Test for RocketJob::Job
module Concerns
  class RestartTest < Minitest::Test
    class RestartableJob < RocketJob::Job
      include RocketJob::Concerns::Restart

      def perform
        'DONE'
      end
    end

    describe RocketJob::Concerns::Restart do
      before do
        # destroy_all could create new instances
        RestartableJob.delete_all
        assert_equal 0, RestartableJob.count
      end

      after do
        @job.destroy if @job && !@job.new_record?
      end

      describe '#create!' do
        it 'queues a new job' do
          @job = RestartableJob.create!
          assert @job.valid?
          refute @job.new_record?
        end
      end

      describe '#save!' do
        it 'queues a new job' do
          @job = RestartableJob.new
          @job.save!
          assert @job.valid?
          refute @job.new_record?
        end
      end

      describe '#abort' do
        it 'queues a new job' do
          @job = RestartableJob.create!
          assert @job.valid?
          refute @job.new_record?
        end
      end

      describe '#complete' do
        it 'queues a new job when destroy_on_complete' do
          @job = RestartableJob.create!(destroy_on_complete: true)
          assert @job.valid?
          refute @job.new_record?
          @job.perform_now
        end

        it 'queues a new job when not destroy_on_complete' do
        end
      end

      describe '#destroy' do
        # it 'does not enqueue a new job when in a final state' do
        #   @job = RestartableJob.create!
        #   assert @job.valid?
        #   refute @job.new_record?
        #   @job.perform_now
        #   assert @job.completed?
        #   assert_equal 1, RestartableJob.count, RestartableJob.all.to_a.ai
        # end

        # it 'enqueues a new job when not in a final state' do
        #   @job = RestartableJob.create!
        #   assert @job.valid?
        #   refute @job.new_record?
        #   @job.perform_now
        #   assert @job.completed?
        #   assert_equal 2, RestartableJob.count, RestartableJob.all.to_a.ai
        #   ap RestartableJob.all.to_a
        #   assert_equal @job.id, RestartableJob.first.id
        #   refute_equal @job.id, RestartableJob.last.id
        # end
      end

      describe '#fail' do
        it 'aborts from queued' do
        end
        it 'aborts from running' do
        end
        it 'aborts from paused' do
        end
      end

      describe 'expiry' do
        it 'stops job from restarting' do
        end
      end

      describe '#initialize_copy' do
        it 'sets job back to queued state' do
        end
        it 'excludes attributes related to running jobs' do
        end
      end

    end
  end
end

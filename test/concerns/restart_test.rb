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
        RestartableJob.delete_all
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

      describe '#abort!' do
        it 'queues a new job on abort' do
          @job = RestartableJob.create!
          @job.abort!
          assert_equal 2, RestartableJob.count
          assert other = RestartableJob.where(id: {'$ne' => @job.id}).first
          refute_equal @job.id, other.id
          assert other.queued?
        end

        it 'does not queue a new job when expired' do
          @job = RestartableJob.create!(expires_at: Time.now - 1.day)
          assert @job.expired?
          @job.abort!
          assert_equal 1, RestartableJob.count
          assert_equal nil, RestartableJob.where(id: {'$ne' => @job.id}).first
        end
      end

      describe '#complete' do
        it 'queues a new job when destroy_on_complete' do
          @job = RestartableJob.create!(destroy_on_complete: true)
          @job.perform_now
          assert @job.completed?, @job.attributes.ai
          assert_equal 1, RestartableJob.count
        end

        it 'queues a new job when not destroy_on_complete' do
          @job = RestartableJob.create!(destroy_on_complete: false)
          @job.perform_now
          assert @job.completed?
          assert_equal 2, RestartableJob.count
        end

        it 'does not queue a new job when expired' do
          @job = RestartableJob.create!(expires_at: Time.now - 1.day)
          @job.perform_now
          assert @job.expired?
          assert @job.completed?
          assert_equal 0, RestartableJob.count
        end
      end

      describe '#destroy' do
        it 'does not enqueue a new job when in a final state' do
          @job = RestartableJob.create!(destroy_on_complete: false)
          @job.perform_now
          assert @job.completed?
          assert_equal 2, RestartableJob.count
          @job.destroy
          assert_equal 1, RestartableJob.count
        end

        it 'enqueues a new job when queued' do
          @job = RestartableJob.create!
          assert @job.queued?
          assert_equal 1, RestartableJob.count
          @job.destroy
          assert_equal 1, RestartableJob.count

          assert other = RestartableJob.last
          refute_equal @job.id, other.id
          assert other.queued?
        end

        it 'enqueues a new job when running' do
          @job = RestartableJob.new
          @job.start!
          assert_equal 1, RestartableJob.count
          @job.destroy
          assert_equal 1, RestartableJob.count

          assert other = RestartableJob.last
          refute_equal @job.id, other.id
          assert other.queued?, other.state
        end

        it 'enqueues a new job when paused' do
          @job = RestartableJob.new
          @job.start
          @job.pause!
          assert @job.paused?
          assert_equal 1, RestartableJob.count
          @job.destroy
          assert_equal 1, RestartableJob.count

          assert other = RestartableJob.last
          refute_equal @job.id, other.id
          assert other.queued?
        end

        it 'does not enqueue a new job when the job is queued and has expired' do
          @job = RestartableJob.create!(destroy_on_complete: false, expires_at: Time.now - 1.day)
          assert @job.queued?
          assert_equal 1, RestartableJob.count
          @job.destroy
          assert_equal 0, RestartableJob.count
        end

        it 'does not enqueue a new job when the job is running and has expired' do
          @job = RestartableJob.new(destroy_on_complete: false, expires_at: Time.now - 1.day)
          @job.start!
          assert @job.running?
          assert @job.expired?
          assert_equal 1, RestartableJob.count
          @job.destroy
          assert_equal 0, RestartableJob.count, RestartableJob.all.to_a.ai
        end

        it 'does not enqueue a new job when the job is paused and has expired' do
          @job = RestartableJob.new(destroy_on_complete: false, expires_at: Time.now - 1.day)
          @job.start
          @job.pause!
          assert @job.paused?
          assert @job.expired?
          assert_equal 1, RestartableJob.count
          @job.destroy
          assert_equal 0, RestartableJob.count, RestartableJob.all.to_a.ai
        end
      end

      describe '#fail' do
        it 'aborts from queued' do
          @job = RestartableJob.new
          assert @job.queued?
          @job.fail
          assert @job.aborted?
        end

        it 'aborts from running' do
          @job = RestartableJob.new
          @job.start
          assert @job.running?
          @job.fail
          assert @job.aborted?
        end

        it 'aborts from paused' do
          @job = RestartableJob.new
          @job.start
          @job.pause
          assert @job.paused?
          @job.fail
          assert @job.aborted?
        end

        it 'does not queue a new job when expired' do
          @job = RestartableJob.new(expires_at: Time.now - 1.day)
          @job.start!
          assert @job.running?
          assert @job.expired?
          assert_equal 1, RestartableJob.count
          assert_equal nil, RestartableJob.where(id: {'$ne' => @job.id}).first
        end
      end

      describe '#create_new_instance' do
        it 'sets job back to queued state' do
          @job = RestartableJob.create!(destroy_on_complete: true)
          @job.perform_now
          assert_equal 1, RestartableJob.count
          assert job2 = RestartableJob.where(id: {'$ne' => @job.id}).first
          assert job2.queued?, job2.attributes.ai
        end

        it 'excludes attributes related to running jobs' do
          @job = RestartableJob.create!(destroy_on_complete: true, expires_at: Time.now + 1.day)
          refute @job.expired?
          @job.perform_now
          assert_equal 1, RestartableJob.count
          assert job2 = RestartableJob.where(id: {'$ne' => @job.id}).first
          assert job2.queued?, job2.attributes.ai

          # Copy across all attributes, except
          @job.attributes.each_pair do |key, value|
            next if RocketJob::Concerns::Restart::RESTART_EXCLUDES.include?(key)
            assert_equal value, job2[key], "Attributes are supposed to be copied across. For #{key}"
          end

          assert_equal :queued, job2.state
          assert job2.created_at
          assert_equal nil, job2.started_at
          assert_equal nil, job2.completed_at
          assert_equal 0, job2.failure_count
          assert_equal nil, job2.worker_name
          assert_equal 0, job2.percent_complete
          assert_equal nil, job2.exception
          assert_equal({}, job2.result)
        end

        it 'copies run_at when it is in the future' do
          @job = RestartableJob.create!(run_at: Time.now + 1.day, destroy_on_complete: true)
          @job.perform_now
          assert_equal 1, RestartableJob.count
          assert job2 = RestartableJob.where(id: {'$ne' => @job.id}).first
          assert job2.run_at, job2.attributes.ai
        end

        it 'does not copy run_at when it is in the past' do
          @job = RestartableJob.create!(run_at: Time.now - 1.day, destroy_on_complete: true)
          @job.perform_now
          assert_equal 1, RestartableJob.count
          assert job2 = RestartableJob.where(id: {'$ne' => @job.id}).first
          assert_equal nil, job2.run_at
        end
      end

    end
  end
end

require_relative '../test_helper'

# Unit Test for RocketJob::Job
module Plugins
  class RestartTest < Minitest::Test
    class RestartableJob < RocketJob::Job
      include RocketJob::Plugins::Restart

      field :start_at, type: Date
      field :end_at, type: Date

      def perform
        self.start_at = Date.today
        self.end_at   = Date.today
        'DONE'
      end
    end

    class RestartablePausableJob < RocketJob::Job
      include RocketJob::Plugins::Restart

      field :start_at, type: Date
      field :end_at, type: Date

      # Job will reload itself during process to check if it was paused.
      self.pausable = true

      def perform
        self.start_at = Date.today
        self.end_at   = Date.today
        'DONE'
      end
    end

    describe RocketJob::Plugins::Restart do
      before do
        RestartableJob.delete_all
        RestartablePausableJob.delete_all
      end

      after do
        @job.delete if @job && !@job.new_record?
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
          assert other = RestartableJob.where(:id.ne => @job.id).first
          refute_equal @job.id, other.id
          assert other.queued?
        end

        it 'does not queue a new job when expired' do
          @job = RestartableJob.create!(expires_at: Time.now - 1.day)
          assert @job.expired?
          @job.abort!
          assert_equal 1, RestartableJob.count
          assert_nil RestartableJob.where(:id.ne => @job.id).first
        end
      end

      describe '#complete' do
        it 'queues a new job when destroy_on_complete' do
          assert_equal 0, RestartableJob.count
          @job = RestartableJob.create!(destroy_on_complete: true)
          @job.perform_now
          assert @job.completed?, @job.attributes.ai
          assert_equal 1, RestartableJob.count, RestartableJob.all.to_a.ai
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

      describe '#pause' do
        it 'does not enqueue a new job when paused' do
          @job = RestartablePausableJob.new
          @job.start
          @job.pause!
          assert @job.paused?
          assert_equal 1, RestartablePausableJob.count
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
          @job = RestartablePausableJob.new
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
          assert_nil RestartableJob.where(:id.ne => @job.id).first
        end
      end

      describe '#create_new_instance' do
        it 'sets job back to queued state' do
          @job = RestartableJob.create!(destroy_on_complete: true)
          @job.perform_now
          assert_equal 1, RestartableJob.count
          assert job2 = RestartableJob.where(:id.ne => @job.id).first
          assert job2.queued?, job2.attributes.ai
        end

        it 'excludes attributes related to running jobs' do
          @job = RestartableJob.create!(destroy_on_complete: true, expires_at: Time.now + 1.day)
          refute @job.expired?
          @job.perform_now
          assert_equal 1, RestartableJob.count
          assert job2 = RestartableJob.where(:id.ne => @job.id).first
          assert job2.queued?, job2.attributes.ai

          assert RestartableJob.rocket_job_restart_attributes.include?(:priority)
          assert RestartableJob.rocket_job_restart_attributes.exclude?(:start_at)
          assert RestartableJob.rocket_job_restart_attributes.exclude?(:end_at)
          assert RestartableJob.rocket_job_restart_attributes.exclude?(:run_at)

          # Copy across all attributes, except
          RestartableJob.rocket_job_restart_attributes.each do |key|
            assert_equal @job.send(key).to_s, job2.send(key).to_s, "Attributes are supposed to be copied across. For #{key}"
          end

          assert_nil job2.start_at
          assert_nil job2.end_at
          assert_equal :queued, job2.state
          assert job2.created_at
          assert_nil job2.started_at
          assert_nil job2.completed_at
          assert_equal 0, job2.failure_count
          assert_nil job2.worker_name
          assert_equal 0, job2.percent_complete
          assert_nil job2.exception
          refute job2.result
        end
      end

    end
  end
end

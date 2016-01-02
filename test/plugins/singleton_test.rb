require_relative '../test_helper'

module Plugins
  # Unit Test for RocketJob::Job
  class SingletonTest < Minitest::Test

    class SingletonJob < RocketJob::Job
      include RocketJob::Plugins::Singleton

      rocket_job do |job|
        job.priority    = 53
        job.description = 'Hello'
      end

      def perform
      end
    end

    describe RocketJob::Plugins::Singleton do
      before do
        SingletonJob.delete_all
      end

      after do
        @job.destroy if @job && !@job.new_record?
      end

      describe '#rocket_job_singleton_active?' do
        it 'returns false if no jobs of this class are active' do
          @job = SingletonJob.new
          assert_equal false, @job.rocket_job_singleton_active?
        end

        it 'excludes self when queued from check' do
          @job = SingletonJob.create
          assert @job.queued?
          assert_equal false, @job.rocket_job_singleton_active?
        end

        it 'excludes self when started from check' do
          @job = SingletonJob.new
          @job.start!
          assert @job.running?
          assert_equal false, @job.rocket_job_singleton_active?
        end

        it 'returns true when other jobs of this class are queued' do
          @job = SingletonJob.create!
          job2 = SingletonJob.new
          assert_equal true, job2.rocket_job_singleton_active?
        end

        it 'returns true when other jobs of this class are running' do
          @job = SingletonJob.new
          @job.start!
          job2 = SingletonJob.new
          assert_equal true, job2.rocket_job_singleton_active?
        end

        it 'returns false when other jobs of this class are not active' do
          @job = SingletonJob.new
          @job.perform_now
          @job.save!
          assert @job.completed?
          job2 = SingletonJob.new
          assert_equal false, job2.rocket_job_singleton_active?
        end
      end

      describe 'validation' do
        it 'passes if another job is not active' do
          @job = SingletonJob.new
          @job.perform_now
          @job.save!
          job2 = SingletonJob.new
          assert_equal true, job2.valid?
        end

        it 'fails if another job is active' do
          @job = SingletonJob.new
          @job.start!
          job2 = SingletonJob.new
          assert_equal false, job2.valid?
          assert_equal ['Another instance of Plugins::SingletonTest::SingletonJob is already queued or running'], job2.errors.messages[:state]
        end

        it 'passes if another job is active, but this job is not' do
          @job = SingletonJob.new
          @job.start!
          job2 = SingletonJob.new
          job2.abort
          assert job2.valid?
          job2.save!
        end
      end

    end
  end
end

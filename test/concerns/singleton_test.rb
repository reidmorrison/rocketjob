require_relative '../test_helper'

# Unit Test for RocketJob::Job
class SingletonTest < Minitest::Test

  class SingletonJob < RocketJob::Job
    include RocketJob::Concerns::Singleton

    rocket_job do |job|
      job.priority    = 53
      job.description = 'Hello'
    end

    def perform
    end
  end

  describe RocketJob::Concerns::Singleton do
    after do
      @job.destroy if @job && !@job.new_record?
    end

    describe '#singleton_job_active?' do
      it 'returns false if no jobs of this class are active' do
        @job = SingletonJob.new
        assert_equal false, @job.singleton_job_active?
      end

      it 'excludes self when queued from check' do
        @job = SingletonJob.create
        assert @job.queued?
        assert_equal false, @job.singleton_job_active?
      end

      it 'excludes self when started from check' do
        @job = SingletonJob.new
        @job.start!
        assert @job.running?
        assert_equal false, @job.singleton_job_active?
      end

      it 'returns true when other jobs of this class are queued' do
        @job = SingletonJob.create!
        job2 = SingletonJob.new
        assert_equal true, job2.singleton_job_active?
      end

      it 'returns true when other jobs of this class are running' do
        @job = SingletonJob.new
        @job.start!
        job2 = SingletonJob.new
        assert_equal true, job2.singleton_job_active?
      end

      it 'returns false when other jobs of this class are not active' do
        @job = SingletonJob.new
        @job.perform_now
        @job.save!
        assert @job.completed?
        job2 = SingletonJob.new
        assert_equal false, job2.singleton_job_active?
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
        assert_equal ['Another instance of this job is already queued or running'], job2.errors.messages[:state]
      end
    end

  end
end

require_relative '../test_helper'

# Unit Test for RocketJob::Job
class DefaultsTest < Minitest::Test

  class ParentJob < RocketJob::Job
    rocket_job do |job|
      job.priority = 53
      job.description = 'Hello'
    end

    def perform
    end
  end

  class ChildJob < ParentJob
    rocket_job do |job|
      job.priority = 72
    end

    def perform
    end
  end

  describe RocketJob::Concerns::Defaults do
    after do
      @job.destroy if @job && !@job.new_record?
    end

    describe '.rocket_job' do
      it 'sets defaults after initialize' do
        @job = ParentJob.new
        assert_equal 53, @job.priority
        assert_equal 'Hello', @job.description
      end

      it 'allows a child to override parent defaults' do
        @job = ChildJob.new
        assert_equal 72, @job.priority
      end

      it 'passes down parent defaults' do
        @job = ChildJob.new
        assert_equal 'Hello', @job.description
      end
    end
  end
end

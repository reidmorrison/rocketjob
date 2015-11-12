require_relative '../test_helper'
require_relative '../jobs/test_job'

# Unit Test for RocketJob::Job
class JobTest < Minitest::Test
  describe RocketJob::Concerns::Persistence do
    before do
      @description = 'Hello World'
      @arguments   = [{key: 'value'}]
      @quiet_job = Jobs::QuietJob.new(
        description:         @description,
        worker_name:         'worker:123'
      )
      @hash_job = Jobs::HashJob.new(
        description:         @description,
        arguments:           [{key: 'value'}],
        destroy_on_complete: false,
        worker_name:         'worker:123'
      )
    end

    after do
      @quiet_job.destroy if @quiet_job && !@quiet_job.new_record?
      @hash_job.destroy if @hash_job && !@hash_job.new_record?
    end

    describe '.config' do
      it 'support multiple databases' do
        assert_equal 'test_rocketjob', RocketJob::Job.collection.db.name
      end
    end

    describe '#reload' do
      it 'handle hash' do
        assert_equal 'value', @hash_job.arguments.first[:key]
        @hash_job.worker_name = nil
        @hash_job.save!
        @hash_job.worker_name = '123'
        @hash_job.reload
        assert @hash_job.arguments.first.is_a?(ActiveSupport::HashWithIndifferentAccess), @hash_job.arguments.first.class.inspect
        assert_equal 'value', @hash_job.arguments.first['key']
        assert_equal 'value', @hash_job.arguments.first[:key]
        assert_equal nil, @hash_job.worker_name
      end
    end

    describe '#save!' do
      it 'save a blank job' do
        @quiet_job.save!
        assert_nil @quiet_job.worker_name
        assert_nil @quiet_job.completed_at
        assert @quiet_job.created_at
        assert_equal @description, @quiet_job.description
        assert_equal false, @quiet_job.destroy_on_complete
        assert_nil @quiet_job.expires_at
        assert_equal @arguments, @quiet_job.arguments
        assert_equal 0, @quiet_job.percent_complete
        assert_equal 51, @quiet_job.priority
        assert_equal 0, @quiet_job.failure_count
        assert_nil @quiet_job.run_at
        assert_nil @quiet_job.started_at
        assert_equal :queued, @quiet_job.state
      end
    end

  end
end

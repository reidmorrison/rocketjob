require_relative '../../test_helper'

module Plugins
  module Job
    # Unit Test for RocketJob::Job
    class PersistenceTest < Minitest::Test

      class PersistJob < RocketJob::Job
        self.priority = 53
        field :data, type: Hash

        def perform(hash)
          hash
        end
      end

      describe RocketJob::Plugins::Job::Persistence do
        before do
          RocketJob::Job.destroy_all
          @description = 'Hello World'
          @data        = {'key' => 'value'}
          @job         = PersistJob.new(
            description:         @description,
            data:                @data,
            destroy_on_complete: false
          )
        end

        after do
          @job.destroy if @job && !@job.new_record?
          @job2.destroy if @job2 && !@job2.new_record?
          @job3.destroy if @job3 && !@job3.new_record?
        end

        describe '.config' do
          it 'support multiple databases' do
            assert_equal 'rocketjob_test', RocketJob::Job.collection.database.name
          end
        end

        describe '.rocket_job' do
          it 'sets defaults after initialize' do
            assert_equal 53, @job.priority
          end
        end

        describe '#reload' do
          it 'handle hash' do
            assert_equal 'value', @job.data['key']
            @job.worker_name = nil
            @job.save!
            @job.worker_name = '123'
            @job.reload
            assert @job.data.is_a?(Hash), @job.data.class.ai
            assert_equal 'value', @job.data['key']
            assert_equal nil, @job.worker_name
          end
        end

        describe '#save!' do
          it 'save a blank job' do
            @job.save!
            assert_nil @job.worker_name
            assert_nil @job.completed_at
            assert @job.created_at
            assert_equal @description, @job.description
            assert_equal false, @job.destroy_on_complete
            assert_nil @job.expires_at
            assert_equal @data, @job.data
            assert_equal 0, @job.percent_complete
            assert_equal 53, @job.priority
            assert_equal 0, @job.failure_count
            assert_nil @job.run_at
            assert_nil @job.started_at
            assert_equal :queued, @job.state
          end
        end

        describe '.counts_by_state' do
          it 'returns states as symbols' do
            @job.start!
            @job2  = PersistJob.create!(data: {key: 'value'})
            @job3  = PersistJob.create!(data: {key: 'value'}, run_at: 1.day.from_now)
            counts = RocketJob::Job.counts_by_state
            assert_equal 4, counts.size, counts.ai
            assert_equal 1, counts[:running]
            assert_equal 2, counts[:queued]
            assert_equal 1, counts[:queued_now]
            assert_equal 1, counts[:scheduled]
          end
        end

      end
    end
  end
end

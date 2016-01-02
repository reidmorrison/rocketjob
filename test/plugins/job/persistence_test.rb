require_relative '../../test_helper'

module Plugins
  module Job
    # Unit Test for RocketJob::Job
    class PersistenceTest < Minitest::Test

      class PersistJob < RocketJob::Job
        rocket_job do |job|
          job.priority = 53
        end

        def perform(hash)
          hash
        end
      end

      describe RocketJob::Plugins::Job::Persistence do
        before do
          @description = 'Hello World'
          @arguments   = [{key: 'value'}]
          @job         = PersistJob.new(
            description:         @description,
            arguments:           [{key: 'value'}],
            destroy_on_complete: false
          )
        end

        after do
          @job.destroy if @job && !@job.new_record?
        end

        describe '.config' do
          it 'support multiple databases' do
            assert_equal 'test_rocketjob', RocketJob::Job.collection.db.name
          end
        end

        describe '.rocket_job' do
          it 'sets defaults after initialize' do
            assert_equal 53, @job.priority
          end
        end

        describe '#reload' do
          it 'handle hash' do
            assert_equal 'value', @job.arguments.first[:key]
            @job.worker_name = nil
            @job.save!
            @job.worker_name = '123'
            @job.reload
            assert @job.arguments.first.is_a?(ActiveSupport::HashWithIndifferentAccess), @job.arguments.first.class.ai
            assert_equal 'value', @job.arguments.first['key']
            assert_equal 'value', @job.arguments.first[:key]
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
            assert_equal @arguments, @job.arguments
            assert_equal 0, @job.percent_complete
            assert_equal 53, @job.priority
            assert_equal 0, @job.failure_count
            assert_nil @job.run_at
            assert_nil @job.started_at
            assert_equal :queued, @job.state
          end
        end

      end
    end
  end
end

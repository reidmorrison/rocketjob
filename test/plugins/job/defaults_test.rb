require_relative '../../test_helper'

module Plugins
  module Job
    class DefaultsTest < Minitest::Test
      class ParentJob < RocketJob::Job
        self.priority    = 53
        self.description = 'Hello'

        def perform
        end
      end

      class ChildJob < ParentJob
        self.priority = 72

        def perform
        end
      end

      describe RocketJob::Plugins::Job do
        after do
          @job.destroy if @job && !@job.new_record?
        end

        describe '.rocket_job' do
          it 'sets defaults after initialize' do
            @job = ParentJob.new
            assert_equal 53, @job.priority
            assert_equal 'Hello', @job.description
          end

          it 'can override defaults on initialize' do
            @job = ParentJob.new(priority: 72, description: 'More')
            assert_equal 72, @job.priority
            assert_equal 'More', @job.description
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
  end
end

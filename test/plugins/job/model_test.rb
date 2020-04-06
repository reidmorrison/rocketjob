require_relative "../../test_helper"

module Plugins
  module Job
    class ModelTest < Minitest::Test
      class SimpleJob < RocketJob::Job
        def perform
          10
        end
      end

      class TwoArgumentJob < RocketJob::Job
        self.priority = 53

        def perform(a, b)
          a + b
        end
      end

      describe RocketJob::Plugins::Job::Model do
        after do
          RocketJob::Job.destroy_all
        end

        describe "#scheduled?" do
          it "returns true if job is queued to run in the future" do
            job = SimpleJob.new(run_at: 1.day.from_now)
            assert_equal true, job.queued?
            assert_equal true, job.scheduled?
            job.start
            assert_equal true, job.running?
            assert_equal false, job.scheduled?
          end

          it "returns false if job is queued and can be run now" do
            job = SimpleJob.new
            assert_equal true, job.queued?
            assert_equal false, job.scheduled?
          end

          it "returns false if job is running" do
            job = SimpleJob.new
            job.start
            assert_equal true, job.running?
            assert_equal false, job.scheduled?
          end
        end

        describe "with queued jobs" do
          before do
            SimpleJob.create!(description: "first")
            SimpleJob.create!(description: "second", run_at: 1.day.from_now)
            SimpleJob.create!(description: "third", run_at: 2.days.from_now)
          end

          describe "#scheduled" do
            it "returns only scheduled jobs" do
              count = 0
              RocketJob::Job.scheduled.each do |job|
                count += 1
                assert job.scheduled?
              end
              assert 2, count
            end
          end

          describe "#queued_now" do
            it "returns only queued jobs, not scheduled ones" do
              count = 0
              RocketJob::Job.queued_now.each do |job|
                count += 1
                refute job.scheduled?, -> { job.ai }
              end
              assert 1, count
            end
          end

          describe "#queued" do
            it "returns all queued jobs" do
              count = 0
              RocketJob::Job.queued.each do |_job|
                count += 1
              end
              assert 3, count
            end
          end
        end
      end
    end
  end
end

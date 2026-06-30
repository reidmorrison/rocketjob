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

        def perform(left, right)
          left + right
        end
      end

      describe RocketJob::Plugins::Job::Model do
        after do
          RocketJob::Job.destroy_all
        end

        describe ".underscore_name" do
          it "derives the name from the class, dropping the Job suffix" do
            assert_equal "plugins/job/model_test/simple", SimpleJob.underscore_name
          end

          it "can be overridden" do
            SimpleJob.underscore_name = "custom_name"

            assert_equal "custom_name", SimpleJob.underscore_name
          ensure
            SimpleJob.instance_variable_set(:@underscore_name, nil)
          end
        end

        describe ".human_name" do
          it "derives a human readable name" do
            assert_equal "Plugins/Job/Model Test/Simple", SimpleJob.human_name
          end

          it "can be overridden" do
            SimpleJob.human_name = "Custom Human"

            assert_equal "Custom Human", SimpleJob.human_name
          ensure
            SimpleJob.instance_variable_set(:@human_name, nil)
          end
        end

        describe ".collective_name" do
          it "derives a pluralized underscored name" do
            assert_equal "plugins/job/model_test/simples", SimpleJob.collective_name
          end

          it "can be overridden" do
            SimpleJob.collective_name = "customs"

            assert_equal "customs", SimpleJob.collective_name
          ensure
            SimpleJob.instance_variable_set(:@collective_name, nil)
          end
        end

        describe "#seconds and #duration" do
          it "measures time in the queue when not yet started" do
            job = SimpleJob.new(created_at: 10.seconds.ago)

            assert_operator job.seconds, :>=, 10
            assert_kind_of String, job.duration
          end

          it "measures elapsed run time while running" do
            job = SimpleJob.new(started_at: 5.seconds.ago)

            assert_operator job.seconds, :>=, 5
          end

          it "measures total run time once completed" do
            job = SimpleJob.new(started_at: 20.seconds.ago, completed_at: 5.seconds.ago)

            assert_in_delta 15, job.seconds, 1
          end
        end

        describe "#expired?" do
          it "is false when there is no expiry" do
            refute_predicate SimpleJob.new, :expired?
          end

          it "is true once the expiry has passed" do
            assert_predicate SimpleJob.new(expires_at: 1.minute.ago), :expired?
          end

          it "is false when the expiry is in the future" do
            refute_predicate SimpleJob.new(expires_at: 1.minute.from_now), :expired?
          end
        end

        describe "#sleeping? #worker_count #worker_names" do
          it "reports no workers for a queued job" do
            job = SimpleJob.new

            assert_equal 0, job.worker_count
            assert_empty job.worker_names
          end

          it "reports a worker for a running, assigned job" do
            job = SimpleJob.new(worker_name: "server:1")
            job.start

            assert_equal 1, job.worker_count
            assert_equal ["server:1"], job.worker_names
            refute_predicate job, :sleeping?
          end

          it "is sleeping when running without an assigned worker" do
            job = SimpleJob.new
            job.start

            assert_predicate job, :sleeping?
          end
        end

        describe "#run_now!" do
          it "clears run_at so the job runs immediately" do
            job = SimpleJob.create!(run_at: 1.day.from_now)
            job.run_now!

            assert_nil job.reload.run_at
          end

          it "does nothing when run_at is already nil" do
            job = SimpleJob.create!
            job.run_now!

            assert_nil job.reload.run_at
          end
        end

        describe "#scheduled_at" do
          it "returns run_at when set" do
            at  = 1.day.from_now
            job = SimpleJob.new(run_at: at)

            assert_equal at.to_i, job.scheduled_at.to_i
          end

          it "falls back to created_at" do
            job = SimpleJob.create!

            assert_equal job.created_at, job.scheduled_at
          end
        end

        describe "#worker_on_server?" do
          it "is false when no worker is assigned" do
            refute SimpleJob.new.worker_on_server?("server:1")
          end

          it "matches the server name prefix of the worker name" do
            job = SimpleJob.new(worker_name: "server:1:thread:2")

            assert job.worker_on_server?("server:1")
            refute job.worker_on_server?("other")
          end
        end

        describe "#status" do
          it "stringifies times and ids for a queued job" do
            job    = SimpleJob.create!
            status = job.status

            assert_equal :queued, status["state"]
            # The BSON::ObjectId and Time values are converted to Strings.
            assert_kind_of String, status["_id"]
            assert_kind_of String, status["created_at"]
          end
        end

        describe "#scheduled?" do
          it "returns true if job is queued to run in the future" do
            job = SimpleJob.new(run_at: 1.day.from_now)

            assert_predicate job, :queued?
            assert_predicate job, :scheduled?
            job.start

            assert_predicate job, :running?
            refute_predicate job, :scheduled?
          end

          it "returns false if job is queued and can be run now" do
            job = SimpleJob.new

            assert_predicate job, :queued?
            refute_predicate job, :scheduled?
          end

          it "returns false if job is running" do
            job = SimpleJob.new
            job.start

            assert_predicate job, :running?
            refute_predicate job, :scheduled?
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

                assert_predicate job, :scheduled?
              end
              assert 2, count
            end
          end

          describe "#queued_now" do
            it "returns only queued jobs, not scheduled ones" do
              count = 0
              RocketJob::Job.queued_now.each do |job|
                count += 1

                refute_predicate job, :scheduled?, -> { job.ai }
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

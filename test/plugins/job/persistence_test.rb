require_relative "../../test_helper"

module Plugins
  module Job
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
          @description = "Hello World"
          @data        = {"key" => "value"}
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

        describe ".config" do
          it "support multiple databases" do
            assert_equal "rocketjob_test", RocketJob::Job.collection.database.name
          end
        end

        describe ".rocket_job" do
          it "sets defaults after initialize" do
            assert_equal 53, @job.priority
          end
        end

        describe "#reload" do
          it "handle hash" do
            assert_equal "value", @job.data["key"]
            @job.worker_name = nil
            @job.save!
            @job.worker_name = "123"
            @job.reload
            assert @job.data.is_a?(Hash), @job.data.class.ai
            assert_equal "value", @job.data["key"]
            assert_nil @job.worker_name
          end
        end

        describe "#save!" do
          it "save a blank job" do
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

        describe ".counts_by_state" do
          it "returns states as symbols" do
            @job.start!
            @job2  = PersistJob.create!(data: {key: "value"})
            @job3  = PersistJob.create!(data: {key: "value"}, run_at: 1.day.from_now)
            counts = RocketJob::Job.counts_by_state
            assert_equal 4, counts.size, counts.ai
            assert_equal 1, counts[:running]
            assert_equal 2, counts[:queued]
            assert_equal 1, counts[:queued_now]
            assert_equal 1, counts[:scheduled]
          end

          it "treats all queued jobs as queued_now when none are scheduled" do
            @job.save!
            @job2  = PersistJob.create!(data: {key: "value"})
            counts = RocketJob::Job.counts_by_state
            assert_equal 2, counts[:queued]
            assert_equal 2, counts[:queued_now]
            refute counts.key?(:scheduled)
          end

          it "returns an empty hash when there are no jobs" do
            assert_equal({}, RocketJob::Job.counts_by_state)
          end
        end

        describe "#create_restart!" do
          it "creates a new queued instance copying copy_on_restart attributes" do
            @job.save!
            assert_equal 1, RocketJob::Job.count
            @job.create_restart!
            assert_equal 2, RocketJob::Job.count
            @job2 = RocketJob::Job.where(:id.ne => @job.id).first
            assert @job2
            assert_equal @description, @job2.description
            assert_equal 53, @job2.priority
            assert_equal false, @job2.destroy_on_complete
            assert @job2.queued?
            # `data` is not a copy_on_restart attribute, so it is not carried over.
            assert_nil @job2.data
          end

          it "applies overrides to the new instance" do
            @job.save!
            @job.create_restart!(priority: 11, description: "Restarted")
            @job2 = RocketJob::Job.where(:id.ne => @job.id).first
            assert_equal 11, @job2.priority
            assert_equal "Restarted", @job2.description
          end

          it "does not create a new instance when the job has expired" do
            @job.expires_at = 1.day.ago
            @job.save!
            assert_equal 1, RocketJob::Job.count
            assert_nil @job.create_restart!
            assert_equal 1, RocketJob::Job.count
          end
        end

        describe "#reload" do
          it "marks an incomplete job complete when destroyed and destroy_on_complete is set" do
            @job2 = PersistJob.create!(data: {key: "value"}, destroy_on_complete: true)
            refute @job2.completed?
            # Simulate the job being destroyed from the database by another process.
            RocketJob::Job.where(id: @job2.id).delete_all
            @job2.reload
            assert @job2.completed?
            assert @job2.completed_at
          end
        end

        describe "#save_with_retry!" do
          it "persists the job and returns true" do
            assert_equal true, @job.save_with_retry!
            refute @job.new_record?
            assert RocketJob::Job.where(id: @job.id).exists?
          end

          it "retries on failure and succeeds once save returns true" do
            calls = 0
            # Fail the first two attempts, then succeed on the third.
            saver = lambda do |*|
              calls += 1
              calls >= 3
            end
            @job.stub(:save, saver) do
              assert @job.save_with_retry!(5, 0)
            end
            assert_equal 3, calls
          end

          it "raises via save! once the retry limit is exhausted" do
            # `save` never succeeds, so the loop exhausts its retries and the
            # final `save!` surfaces the failure.
            @job.stub(:save, false) do
              assert_raises(::Mongoid::Errors::Callback) do
                @job.save_with_retry!(2, 0)
              end
            end
          end
        end
      end
    end
  end
end

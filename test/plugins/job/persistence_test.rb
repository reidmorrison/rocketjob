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

      class PersistBatchJob < RocketJob::Job
        include RocketJob::Batch

        input_category slice_size: 10
        output_category format: :csv

        def perform(record)
          record
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

            assert_kind_of Hash, @job.data, @job.data.class.ai
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
            refute @job.destroy_on_complete
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
            refute @job2.destroy_on_complete
            assert_predicate @job2, :queued?
            # `data` is not a copy_on_restart attribute, so it is not carried over.
            assert_nil @job2.data
          end

          it "does not copy what happened to the job that it restarts" do
            @job.save!
            @job.start!
            @job.fail!(nil, "Oh no")
            @job.create_restart!
            @job2 = RocketJob::Job.where(:id.ne => @job.id).first

            assert_predicate @job2, :queued?
            assert_nil @job2.started_at
            assert_nil @job2.completed_at
            assert_equal 0, @job2.failure_count
            assert_nil @job2.worker_name
            assert_equal 0, @job2.percent_complete
            assert_nil @job2.exception
          end

          it "applies overrides to the new instance" do
            @job.save!
            @job.create_restart!(priority: 11, description: "Restarted")
            @job2 = RocketJob::Job.where(:id.ne => @job.id).first

            assert_equal 11, @job2.priority
            assert_equal "Restarted", @job2.description
          end

          it "keeps the categories of a batch job, with their settings" do
            job = PersistBatchJob.new
            job.input_category.slice_size = 25
            job.output_category.format    = :json
            job.output_category.nils      = true
            job.output_category.file_name = "output.json.gz"
            job.save!
            job.create_restart!

            restarted = RocketJob::Job.where(:id.ne => job.id).first

            assert_equal 25, restarted.input_category.slice_size
            assert_equal :json, restarted.output_category.format
            assert restarted.output_category.nils
            assert_equal "output.json.gz", restarted.output_category.file_name.to_s
          ensure
            RocketJob::Job.destroy_all
          end

          it "reads the header row of the next run's own file, rather than the one that its last upload read" do
            job                       = PersistBatchJob.new
            job.input_category.format = :csv
            job.upload(StringIO.new("first_name,zip\nJack,12345\n"), file_name: "a.csv")
            job.save!
            job.create_restart!

            restarted = RocketJob::Job.where(:id.ne => job.id).first

            assert_nil restarted.input_category.columns
            refute restarted.input_category.header_uploaded
            assert_equal 1, restarted.upload(StringIO.new("name,city\nJill,Boston\n"), file_name: "b.csv")
            assert_equal %w[name city], restarted.input_category.columns
          ensure
            RocketJob::Job.all.each(&:cleanup!)
            RocketJob::Job.destroy_all
          end

          it "creates the next run of a job that Rocket Job 7 saved with the :array mode, whose upload raises" do
            job = PersistBatchJob.create!
            PersistBatchJob.collection.update_one({_id: job.id}, {"$set" => {"input_categories.0.mode" => "array"}})
            job = PersistBatchJob.find(job.id)
            job.create_restart!

            restarted = RocketJob::Job.where(:id.ne => job.id).first

            assert_equal :array, restarted.input_category.mode
            error = assert_raises(ArgumentError) do
              restarted.upload(StringIO.new("name\nJill\n"), file_name: "b.csv")
            end
            assert_includes error.message, "mode: :array was removed in Rocket Job v8"
          ensure
            RocketJob::Job.destroy_all
          end

          it "keeps columns that no upload read, such as those of a job that Rocket Job 7 saved, so its upload raises" do
            job                        = PersistBatchJob.new
            job.input_category.format  = :csv
            job.input_category.columns = %w[name zip]
            job.save!
            job.create_restart!

            restarted = RocketJob::Job.where(:id.ne => job.id).first

            assert_equal %w[name zip], restarted.input_category.columns
            error = assert_raises(ArgumentError) do
              restarted.upload(StringIO.new("name,zip\nJill,02101\n"), file_name: "b.csv")
            end
            assert_includes error.message, "Input category main holds columns that no upload read from a file"
          ensure
            RocketJob::Job.destroy_all
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

            refute_predicate @job2, :completed?
            # Simulate the job being destroyed from the database by another process.
            RocketJob::Job.where(id: @job2.id).delete_all
            @job2.reload

            assert_predicate @job2, :completed?
            assert @job2.completed_at
          end
        end

        describe "#save_with_retry!" do
          it "persists the job and returns true" do
            assert @job.save_with_retry!
            refute_predicate @job, :new_record?
            assert_predicate RocketJob::Job.where(id: @job.id), :exists?
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

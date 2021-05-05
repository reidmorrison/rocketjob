require_relative "../test_helper"

module Batch
  class StatisticsTest < Minitest::Test
    # This job adds each callback as they run into an array
    class BatchSlicesJob < RocketJob::Job
      include RocketJob::Batch
      include RocketJob::Batch::Statistics

      field :header, type: String

      def perform(record)
        if record.even?
          statistics_inc("even")
        else
          statistics_inc(odd: 1, "and.more" => 2)
        end
      end
    end

    class RetryJob < RocketJob::Job
      include RocketJob::Batch
      include RocketJob::Batch::Statistics

      self.destroy_on_complete = false

      input_category slice_size: 5

      field :exception_record, type: Integer

      def perform(record)
        # Ensure stats before the exception are not duplicated
        statistics_inc(:record_count)

        statistics_inc(record.to_s => record)

        raise(ArgumentError, "This is the bad record") if record == exception_record

        logger.info("Processing record: #{record}")

        record
      end
    end

    describe RocketJob::Batch::Statistics::Stats do
      describe "#inc_key" do
        describe "in_memory" do
          let :stats do
            RocketJob::Batch::Statistics::Stats.new(Hash.new(0))
          end

          before do
            assert_nil stats.stats
            assert_equal({}, stats.in_memory)
          end

          it "handles empty key" do
            stats.inc_key("")
            assert_nil stats.stats
            assert_equal({}, stats.in_memory)
          end

          it "handles nil key" do
            stats.inc_key(nil)
            assert_nil stats.stats
            assert_equal({}, stats.in_memory)
          end

          it "increments simple key" do
            stats.inc_key(:user_count)
            assert_nil stats.stats
            assert_equal({"user_count" => 1}, stats.in_memory)
          end

          it "increments nested key" do
            stats.inc_key("us.na.user.count")
            assert_nil stats.stats
            assert_equal({"us" => {"na" => {"user" => {"count" => 1}}}}, stats.in_memory)
          end
        end

        describe "stored" do
          let :stats do
            RocketJob::Batch::Statistics::Stats.new
          end

          before do
            assert_nil stats.in_memory
            assert_equal({}, stats.stats)
          end

          it "handles empty key" do
            stats.inc_key("")
            assert_nil stats.in_memory
            assert_equal({}, stats.stats)
          end

          it "handles nil key" do
            stats.inc_key(nil)
            assert_nil stats.in_memory
            assert_equal({}, stats.stats)
          end

          it "increments simple key" do
            stats.inc_key(:user_count)
            assert_nil stats.in_memory
            assert_equal({"statistics.user_count" => 1}, stats.stats)
          end

          it "increments nested key" do
            stats.inc_key("us.na.user.count")
            assert_nil stats.in_memory
            assert_equal({"statistics.us.na.user.count" => 1}, stats.stats)
          end
        end
      end

      describe "#inc" do
        describe "in_memory" do
          let :stats do
            RocketJob::Batch::Statistics::Stats.new(Hash.new(0))
          end

          before do
            assert_nil stats.stats
            assert_equal({}, stats.in_memory)
          end

          it "handles empty key" do
            stats.inc("" => 21)
            assert_nil stats.stats
            assert_equal({}, stats.in_memory)
          end

          it "handles nil key" do
            stats.inc(nil => 24)
            assert_nil stats.stats
            assert_equal({}, stats.in_memory)
          end

          it "increments simple key" do
            stats.inc(user_count: 24)
            assert_nil stats.stats
            assert_equal({"user_count" => 24}, stats.in_memory)
          end

          it "increments nested key" do
            stats.inc("us.na.user.count" => 23)
            assert_nil stats.stats
            assert_equal({"us" => {"na" => {"user" => {"count" => 23}}}}, stats.in_memory)
          end
        end

        describe "stored" do
          let :stats do
            RocketJob::Batch::Statistics::Stats.new
          end

          before do
            assert_nil stats.in_memory
            assert_equal({}, stats.stats)
          end

          it "handles empty key" do
            stats.inc("" => 21)
            assert_nil stats.in_memory
            assert_equal({}, stats.stats)
          end

          it "handles nil key" do
            stats.inc(nil => 21)
            assert_nil stats.in_memory
            assert_equal({}, stats.stats)
          end

          it "increments simple key" do
            stats.inc(user_count: 24)
            assert_nil stats.in_memory
            assert_equal({"statistics.user_count" => 24}, stats.stats)
          end

          it "increments nested key" do
            stats.inc("us.na.user.count" => 23)
            assert_nil stats.in_memory
            assert_equal({"statistics.us.na.user.count" => 23}, stats.stats)
          end
        end
      end
    end

    describe RocketJob::Batch::Statistics do
      let :job do
        job                           = BatchSlicesJob.new
        job.input_category.slice_size = 4
        job.upload do |stream|
          7.times.each { |i| stream << i }
        end
        job
      end

      after do
        BatchSlicesJob.destroy_all
      end

      describe "#statistics_inc" do
        it "in memory model" do
          job.perform_now
          assert job.completed?, job.attributes.ai
          assert_equal %w[and even odd], job.statistics.keys.sort
          assert_equal 4, job.statistics["even"], job.statistics.ai
          assert_equal 3, job.statistics["odd"], job.statistics.ai
          assert_equal({"more" => 6}, job.statistics["and"], job.statistics.ai)
        end

        it "persisted model" do
          job.save!
          job.perform_now
          assert job.completed?, job.attributes.ai
          assert_equal %w[and even odd], job.statistics.keys.sort
          assert_equal 4, job.statistics["even"], job.statistics.ai
          assert_equal 3, job.statistics["odd"], job.statistics.ai
          assert_equal({"more" => 6}, job.statistics["and"], job.statistics.ai)
          job.reload
          assert_equal %w[and even odd], job.statistics.keys.sort
          assert_equal 4, job.statistics["even"], job.statistics.ai
          assert_equal 3, job.statistics["odd"], job.statistics.ai
          assert_equal({"more" => 6}, job.statistics["and"], job.statistics.ai)
        end

        it "logs statistics on completion" do
          description = nil
          payload     = nil
          job.logger.stub(:info, ->(description_, payload_) { description = description_, payload = payload_ }) do
            job.perform_now
          end
          assert job.completed?, job.attributes.ai

          assert_equal "Complete", description.first
          assert_equal :complete, payload[:event]
          assert_equal :running, payload[:from]
          assert_equal :completed, payload[:to]

          assert statistics = payload[:statistics]
          assert_equal %w[and even odd], statistics.keys.sort
          assert_equal 4, statistics["even"], statistics.ai
          assert_equal 3, statistics["odd"], statistics.ai
          assert_equal({"more" => 6}, statistics["and"], statistics.ai)
        end

        it "logs statistics on failure" do
          description = nil
          payload     = nil
          job.start
          job.statistics = {"bad" => "one"}
          job.logger.stub(:info, ->(description_, payload_) { description = description_, payload = payload_ }) do
            job.fail
          end
          assert job.failed?, job.attributes.ai

          assert_equal "Fail", description.first
          assert_equal :fail, payload[:event]
          assert_equal :running, payload[:from]
          assert_equal :failed, payload[:to]

          assert statistics = payload[:statistics]
          assert_equal({"bad" => "one"}, statistics)
        end

        describe "with Retry Job" do
          let(:record_count) { 24 }

          let(:exception_record) { 4 }

          let :job do
            job = RetryJob.new(exception_record: exception_record)
            job.upload do |records|
              (1..record_count).each { |i| records << i }
            end
            job.start
            job
          end

          after do
            RetryJob.destroy_all
          end

          it "handles retries" do
            job.rocket_job_work(RocketJob::Worker.new, false)
            assert job.failed?, -> { job.as_document.ai }
            job.exception_record = nil
            job.retry
            job.perform_now
            assert job.completed?, -> { job.as_document.ai }
            stats = job.statistics.dup

            assert_equal record_count, stats.delete("record_count")
            (1..record_count).each do |count|
              assert_equal count, stats.delete(count.to_s)
            end
            assert stats.empty?, stats.ai
          end

          it "handles persisted retries" do
            job.save!
            job.rocket_job_work(RocketJob::Worker.new, false)
            assert job.failed?, -> { job.as_document.ai }
            job.exception_record = nil
            job.retry!
            job.perform_now
            assert job.completed?, -> { job.as_document.ai }
            stats = job.statistics.dup

            assert_equal record_count, stats.delete("record_count")
            (1..record_count).each do |count|
              assert_equal count, stats.delete(count.to_s)
            end
            assert stats.empty?, stats.ai
          end
        end
      end
    end
  end
end

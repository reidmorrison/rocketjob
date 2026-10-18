require_relative "../test_helper"

module Batch
  # A batch job that fails in its before_batch callbacks, after they uploaded its input, uploads it again when it is
  # retried, without duplicating it.
  class BeforeBatchRetryTest < Minitest::Test
    class UploadingJob < RocketJob::Job
      include RocketJob::Batch

      self.destroy_on_complete = false

      field :csv, type: String
      field :lines, type: Array
      field :fail_before_batch, type: Mongoid::Boolean, default: true

      input_category format: :csv
      input_category name: :lines
      output_category

      before_batch :upload_input

      def perform(record)
        record
      end

      private

      def upload_input
        upload(StringIO.new(csv), file_name: "people.csv") if csv
        upload(category: :lines) { |io| lines.each { |line| io << line } } if lines
        raise "before_batch failed" if fail_before_batch
      end
    end

    describe "a batch job retried after its before_batch callbacks uploaded its input" do
      let(:worker) { RocketJob::Worker.new }

      after do
        @job&.cleanup!
        @job&.destroy
      end

      # Runs the job until its before_batch callbacks fail, as a server's worker does.
      def fail_in_before_batch(job)
        job.start!
        job.rocket_job_work(worker, false)
        job.reload
      end

      # Retries the job, unless it was, then runs it to completion, as a server's worker does.
      def retry_and_run(job)
        job.fail_before_batch = false
        job.failed? ? job.retry! : job.save!
        job.start!
        job.rocket_job_work(worker, false)
        job.reload
      end

      it "fails while holding what its before_batch callbacks uploaded" do
        @job = UploadingJob.create!(csv: "Name,Age\nJack,21\nJill,22\n")
        fail_in_before_batch(@job)

        assert_predicate @job, :failed?
        assert_equal :before, @job.sub_state
        assert_equal 1, @job.input.count
        assert_equal 2, @job.record_count
        assert @job.input_category.header_uploaded
      end

      it "removes what they uploaded, and restores the job, when it is retried" do
        @job = UploadingJob.create!(csv: "Name,Age\nJack,21\nJill,22\n")
        fail_in_before_batch(@job)
        @job.retry!

        assert_predicate @job, :queued?
        assert_equal 0, @job.input.count
        assert_nil @job.record_count
        assert_nil @job.input_category.columns
        refute @job.input_category.header_uploaded
        assert_nil @job.before_batch_state
      end

      it "uploads the input again, without the records of the failed run" do
        @job = UploadingJob.create!(csv: "Name,Age\nJack,21\nJill,22\n")
        fail_in_before_batch(@job)
        retry_and_run(@job)

        assert_predicate @job, :completed?, -> { @job.as_document.ai }
        assert_equal 2, @job.record_count
        assert_equal %w[name age], @job.input_category.columns
        assert_nil @job.before_batch_state
        output = []
        @job.output.each { |slice| output.concat(slice.to_a) }

        assert_equal [{"name" => "Jack", "age" => "21"}, {"name" => "Jill", "age" => "22"}], output
      end

      it "keeps the slices that were uploaded before the job started" do
        @job = UploadingJob.new(lines: %w[c])
        @job.upload(category: :lines) { |io| %w[a b].each { |line| io << line } }
        @job.save!
        fail_in_before_batch(@job)

        assert_equal 3, @job.record_count
        assert_equal 2, @job.input(:lines).count

        @job.retry!

        assert_equal 2, @job.record_count
        assert_equal [%w[a b]], @job.input(:lines).collect(&:to_a)

        retry_and_run(@job)

        assert_equal 3, @job.record_count
        assert_equal [%w[a b], %w[c]], @job.input(:lines).collect(&:to_a).sort
      end

      it "removes what they uploaded when the job is requeued from a server that died" do
        @job = UploadingJob.create!(csv: "Name,Age\nJack,21\n")
        @job.start!
        @job.sub_state          = :before
        @job.worker_name        = "dead:1234:1"
        @job.before_batch_state = @job.send(:rocketjob_before_batch_state)
        @job.upload(StringIO.new(@job.csv), file_name: "people.csv")
        @job.save!
        @job.requeue!("dead:1234")

        assert_predicate @job, :queued?
        assert_equal 0, @job.input.count
        refute @job.input_category.header_uploaded
      end

      it "leaves a job saved before before_batch_state as it is when it is retried" do
        @job = UploadingJob.create!(csv: "Name,Age\nJack,21\n")
        fail_in_before_batch(@job)
        @job.unset(:before_batch_state)
        @job.reload
        @job.retry!

        assert_equal 1, @job.input.count
        assert_equal 1, @job.record_count
      end
    end
  end
end

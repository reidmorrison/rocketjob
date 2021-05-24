require_relative "../test_helper"

module Jobs
  class UploadFileJobTest < Minitest::Test
    class TestJob < RocketJob::Job
      field :upload_file_name, type: String

      def upload(file_name)
        self.upload_file_name = file_name
      end

      def perform
      end
    end

    class BatchTestJob < RocketJob::Job
      include RocketJob::Batch

      # An input_category of :main is automatically created if none is specified

      # Collect output from this job
      output_category

      field :user_id, type: Integer

      def perform(row)
        row
      end
    end

    class BadJob < RocketJob::Job
      def perform
      end
    end

    describe RocketJob::Jobs::UploadFileJob do
      before do
        RocketJob::Job.delete_all
      end

      let :job do
        RocketJob::Jobs::UploadFileJob.new(
          job_class_name:   UploadFileJobTest::TestJob.name,
          upload_file_name: __FILE__
        )
      end

      let :batch_job do
        RocketJob::Jobs::UploadFileJob.new(
          job_class_name:   UploadFileJobTest::BatchTestJob.name,
          upload_file_name: IOStreams.path("test", "batch", "files", "test.csv"),
          properties:       {
            "user_id"           => 341,
            "input_categories"  => [
              {"format" => "csv"}
            ],
            "output_categories" => [
              {
                "format"  => "csv",
                "columns" => %w[first_name last_name]
              }
            ]
          }
        )
      end

      describe "#valid?" do
        it "with valid job and upload_file_name" do
          assert job.valid?
        end

        it "validates upload_file_name" do
          job.upload_file_name = ""
          refute job.valid?
          assert_includes job.errors.messages[:upload_file_name], "Upload file name can't be blank."
        end

        it "validates file does not exist" do
          job.upload_file_name = "/tmp/blah"
          refute job.valid?
          assert_includes job.errors.messages[:upload_file_name], "Upload file: /tmp/blah does not exist."
        end

        it "allows urls other than file for upload_file_name" do
          job.upload_file_name = "https://server/path"
          assert job.valid?, job.errors.messages
        end

        it "checks the filesystem if the url scheme is file for upload_file_name" do
          job.upload_file_name = "file:/foo/blah"
          refute job.valid?
        end

        it "validates job_class_name" do
          job.job_class_name = UploadFileJobTest::BadJob.name
          refute job.valid?
          message = "Jobs::UploadFileJobTest::BadJob must implement any one of: :upload :upload_file_name= :full_file_name= instance methods"
          assert_includes job.errors.messages[:job_class_name], message
        end
      end

      describe "#perform" do
        it "creates the job" do
          job.perform_now

          assert_equal 1, UploadFileJobTest::TestJob.count
          assert UploadFileJobTest::TestJob.first
        end

        it "calls upload" do
          job.perform_now

          assert job = UploadFileJobTest::TestJob.first
          assert_equal __FILE__, job.upload_file_name
        end

        it "calls upload with original_file_name" do
          batch_job.perform_now

          assert created_job = UploadFileJobTest::BatchTestJob.first
          assert_equal "test/batch/files/test.csv", created_job.upload_file_name.to_s
        end

        it "retains the original_file_name when present" do
          batch_job.original_file_name = "file.rb"
          batch_job.perform_now

          assert created_job = UploadFileJobTest::BatchTestJob.first
          assert_equal "file.rb", created_job.input_category.file_name.to_s
          assert_equal "file.rb", created_job.upload_file_name.to_s
        end

        it "retains input and output categories" do
          batch_job.perform_now

          assert created_job = UploadFileJobTest::BatchTestJob.first
          assert_equal :csv, created_job.input_category.format
          assert_equal :csv, created_job.output_category.format
          assert_equal %w[first_name last_name], created_job.output_category.columns
        end
      end
    end
  end
end

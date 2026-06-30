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

    # Responds to upload_file_name= but not #upload.
    class UploadNameJob < RocketJob::Job
      field :upload_file_name, type: String

      def perform
      end
    end

    # Responds to full_file_name= but not #upload or upload_file_name=.
    class FullNameJob < RocketJob::Job
      field :full_file_name, type: String

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
          assert_predicate job, :valid?
        end

        it "validates upload_file_name" do
          job.upload_file_name = ""

          refute_predicate job, :valid?
          assert_includes job.errors.messages[:upload_file_name], "Upload file name can't be blank."
        end

        it "validates file does not exist" do
          job.upload_file_name = "/tmp/blah"

          refute_predicate job, :valid?
          assert_includes job.errors.messages[:upload_file_name], "Upload file: /tmp/blah does not exist."
        end

        it "allows urls other than file for upload_file_name" do
          job.upload_file_name = "https://server/path"

          assert_predicate job, :valid?, job.errors.messages
        end

        it "checks the filesystem if the url scheme is file for upload_file_name" do
          job.upload_file_name = "file:/foo/blah"

          refute_predicate job, :valid?
        end

        it "validates job_class_name" do
          job.job_class_name = UploadFileJobTest::BadJob.name

          refute_predicate job, :valid?
          message = "Jobs::UploadFileJobTest::BadJob must implement any one of: :upload :upload_file_name= :full_file_name= instance methods"

          assert_includes job.errors.messages[:job_class_name], message
        end

        it "validates the job class inherits from RocketJob::Job" do
          job.job_class_name = "Hash"

          refute_predicate job, :valid?
          assert_includes job.errors.messages[:job_class_name],
                          "Model Hash must be defined and inherit from RocketJob::Job"
        end

        it "is valid when the job class name cannot be resolved" do
          # job_class rescues NameError and returns nil, so the class based
          # validations are skipped.
          job.job_class_name = "No::Such::Constant"

          assert_predicate job, :valid?, job.errors.messages
        end

        it "rejects unknown top level properties" do
          job.properties = {"does_not_exist" => 1}

          refute_predicate job, :valid?
          assert(job.errors.messages[:properties].any? { |m| m.include?("does_not_exist") })
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

        it "assigns the supplied job_id to the downstream job" do
          id         = BSON::ObjectId.new
          job.job_id = id
          job.perform_now

          assert created_job = UploadFileJobTest::TestJob.first
          assert_equal id, created_job.id
        end

        it "assigns upload_file_name when the job has no #upload method" do
          job.job_class_name = UploadFileJobTest::UploadNameJob.name
          job.perform_now

          assert created_job = UploadFileJobTest::UploadNameJob.first
          assert_equal __FILE__, created_job.upload_file_name
        end

        it "assigns full_file_name when that is the only writer available" do
          job.job_class_name = UploadFileJobTest::FullNameJob.name
          job.perform_now

          assert created_job = UploadFileJobTest::FullNameJob.first
          assert_equal __FILE__, created_job.full_file_name
        end
      end
    end
  end
end

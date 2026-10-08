require_relative "../test_helper"

module Jobs
  class CopyFileJobTest < Minitest::Test
    describe RocketJob::Jobs::CopyFileJob do
      after do
        RocketJob::Jobs::CopyFileJob.delete_all
      end

      def create_job(target_url, **)
        RocketJob::Jobs::CopyFileJob.create!(source_url: "/tmp/source.csv", target_url: target_url, **)
      end

      describe "#description" do
        it "names the target without the credentials in its url" do
          job = create_job("sftp://jack:secret@sftp.example.org/uploads/source.csv")

          assert_equal "Copying to sftp://sftp.example.org/uploads/source.csv", job.description
        end

        it "names the target without the query of its url" do
          job = create_job("https://example.org/uploads/source.csv?token=secret")

          assert_equal "Copying to https://example.org/uploads/source.csv", job.description
        end

        it "names an S3 target without loading the AWS SDK" do
          job = create_job("s3://bucket/uploads/source.csv")

          assert_equal "Copying to s3://bucket/uploads/source.csv", job.description
        end

        it "leaves out a target whose url is not valid" do
          job = create_job("ftp://jack:secret@ftp.example.org/source.csv")

          assert_equal "Copying file", job.description
        end

        it "keeps a supplied description" do
          job = create_job("sftp://sftp.example.org/uploads/source.csv", description: "Nightly export")

          assert_equal "Nightly export", job.description
        end
      end
    end
  end
end

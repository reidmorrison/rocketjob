require_relative "../test_helper"

module Jobs
  class CopyFileJobTest < Minitest::Test
    describe RocketJob::Jobs::CopyFileJob do
      let(:dir) { Dir.mktmpdir("copy_file_job") }

      let(:source_url) { File.join(dir, "source.csv.gz") }

      let(:target_url) { File.join(dir, "target.csv.gz") }

      # The bytes of the source file, as they are stored, compressed.
      let(:stored) do
        IOStreams.path(source_url).write("name\nJosé\n")
        File.binread(source_url)
      end

      after do
        FileUtils.rm_rf(dir)
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

        it "leaves out a target that cannot be created in this process" do
          job = create_job("ftp://jack:secret@ftp.example.org/source.csv")

          assert_equal "Copying file", job.description
        end

        it "keeps a supplied description" do
          job = create_job("sftp://sftp.example.org/uploads/source.csv", description: "Nightly export")

          assert_equal "Nightly export", job.description
        end
      end

      describe "#perform" do
        it "copies the file as it is stored with the default streams, without a deprecation warning" do
          stored
          job = RocketJob::Jobs::CopyFileJob.new(source_url: source_url, target_url: target_url)

          assert_silent { job.perform_now }
          assert_equal stored, File.binread(target_url)
        end

        it "applies the streams after none" do
          stored
          job = RocketJob::Jobs::CopyFileJob.new(
            source_url:     source_url,
            target_url:     File.join(dir, "target.csv"),
            source_streams: {"none" => nil, "gz" => nil},
            target_streams: {}
          )
          job.perform_now

          assert_equal "name\nJosé\n".b, File.binread(File.join(dir, "target.csv"))
        end
      end
    end
  end
end

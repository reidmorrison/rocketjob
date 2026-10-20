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

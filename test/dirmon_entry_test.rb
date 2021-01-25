require_relative "test_helper"

class DirmonEntryTest < Minitest::Test
  class TestJob < RocketJob::Job
    # Dirmon will store the filename in this property when starting the job
    field :upload_file_name, type: String

    field :user_id, type: Integer

    def perform
      # Do something with the file name stored in :upload_file_name
    end
  end

  describe RocketJob::DirmonEntry do
    let :archive_directory do
      "/tmp/archive_directory"
    end

    let :archive_path do
      IOStreams.path(archive_directory)
    end

    let :dirmon_entry do
      dirmon_entry = RocketJob::DirmonEntry.new(
        name:              "Test",
        job_class_name:    "DirmonEntryTest::TestJob",
        pattern:           "test/files/**",
        properties:        {user_id: 341},
        archive_directory: archive_directory
      )
      dirmon_entry.enable!
      assert dirmon_entry.valid?, dirmon_entry.errors.messages.ai
      dirmon_entry
    end

    before do
      RocketJob::Jobs::DirmonJob.delete_all
      RocketJob::Jobs::UploadFileJob.delete_all
      RocketJob::DirmonEntry.delete_all
    end

    describe ".config" do
      it "support multiple databases" do
        assert_equal "rocketjob_test", RocketJob::DirmonEntry.collection.database.name
      end
    end

    describe "#job_class" do
      describe "with a nil job_class_name" do
        it "return nil" do
          entry = RocketJob::DirmonEntry.new
          assert_nil entry.job_class
        end
      end

      describe "with an unknown job_class_name" do
        it "return nil" do
          entry = RocketJob::DirmonEntry.new(job_class_name: "FakeJobThatDoesNotExistAnyWhereIPromise")
          assert_nil entry.job_class
        end
      end

      describe "with a valid job_class_name" do
        it "return job class" do
          entry = RocketJob::DirmonEntry.new(job_class_name: "RocketJob::Job")
          assert_equal RocketJob::Job, entry.job_class
          assert_equal 0, entry.properties.size
        end
      end
    end

    describe ".whitelist_paths" do
      it "default to []" do
        assert_equal [], RocketJob::DirmonEntry.whitelist_paths
      end
    end

    describe ".add_whitelist_path" do
      after do
        RocketJob::DirmonEntry.whitelist_paths.each { |path| RocketJob::DirmonEntry.delete_whitelist_path(path) }
      end

      it "convert relative path to an absolute one" do
        path = IOStreams.path("test/files").realpath.to_s
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path("test/files")
        assert_equal [path], RocketJob::DirmonEntry.whitelist_paths
      end

      it "prevent duplicates" do
        path = IOStreams.path("test/files").realpath.to_s
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path("test/files")
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path("test/files")
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path(path)
        assert_equal [path], RocketJob::DirmonEntry.whitelist_paths
      end
    end

    describe "#fail!" do
      it "fail with message" do
        dirmon_entry.fail!("myworker:2323", "oh no")
        assert dirmon_entry.failed?
        assert_equal "RocketJob::DirmonEntryException", dirmon_entry.exception.class_name
        assert_equal "oh no", dirmon_entry.exception.message
      end

      it "fail with exception" do
        exception = nil
        begin
          RocketJob.blah
        rescue Exception => e
          exception = e
        end
        dirmon_entry.fail!("myworker:2323", exception)

        assert_equal true, dirmon_entry.failed?
        assert_equal exception.class.name.to_s, dirmon_entry.exception.class_name
        assert dirmon_entry.exception.message.include?("undefined method"), dirmon_entry.attributes.inspect
      end
    end

    describe "#validate" do
      it "strip_whitespace" do
        dirmon_entry.pattern           = " test/files/*"
        dirmon_entry.archive_directory = " test/archive/ "
        assert dirmon_entry.valid?
        assert_equal "test/files/*", dirmon_entry.pattern
        assert_equal "test/archive/", dirmon_entry.archive_directory
      end

      describe "pattern" do
        it "present" do
          dirmon_entry.pattern = nil
          refute dirmon_entry.valid?
          assert_equal ["can't be blank"], dirmon_entry.errors[:pattern], dirmon_entry.errors.messages.ai
        end
      end

      describe "job_class_name" do
        it "ensure presence" do
          dirmon_entry.job_class_name = nil
          refute dirmon_entry.valid?
          assert_equal ["can't be blank"], dirmon_entry.errors[:job_class_name], dirmon_entry.errors.messages.ai
        end

        it "is a RocketJob::Job" do
          dirmon_entry.job_class_name = "String"
          refute dirmon_entry.valid?
          assert_equal ["Job String must be defined and inherit from RocketJob::Job"], dirmon_entry.errors[:job_class_name], dirmon_entry.errors.messages.ai
        end

        it "is invalid" do
          dirmon_entry.job_class_name = "Blah"
          refute dirmon_entry.valid?
          assert_equal ["Job Blah must be defined and inherit from RocketJob::Job"], dirmon_entry.errors[:job_class_name], dirmon_entry.errors.messages.ai
        end
      end

      describe "properties" do
        it "are valid" do
          dirmon_entry.properties = {user_id: 123}
          assert dirmon_entry.valid?, dirmon_entry.errors.messages.ai
        end

        it "not valid" do
          dirmon_entry.properties = {blah: 123}
          refute dirmon_entry.valid?
          assert_equal ["Unknown Property: Attempted to set a value for :blah which is not allowed on the job DirmonEntryTest::TestJob"], dirmon_entry.errors[:properties], dirmon_entry.errors.messages.ai
        end
      end
    end

    describe "with valid entry" do
      let :file do
        file = Tempfile.new("archive")
        File.open(file.path, "w") { |io| io.write("Hello World") }
        file
      end

      let :file_name do
        file.path
      end

      let :iopath do
        IOStreams.path(file_name)
      end

      after do
        file.delete
        RocketJob::Jobs::DirmonJob.delete_all
      end

      describe "#each" do
        it "without archive path" do
          dirmon_entry.archive_directory = nil
          files                          = []
          dirmon_entry.each { |file_name| files << file_name }
          assert_nil dirmon_entry.archive_directory
          assert_equal 1, files.count
          assert_equal IOStreams.path("test/files/text.txt").realpath, files.first
        end

        it "with archive path" do
          files = []
          dirmon_entry.each do |file_name|
            files << file_name
          end
          assert_equal 1, files.count
          assert_equal IOStreams.path("test/files/text.txt").realpath, files.first
        end

        it "with case-insensitive pattern" do
          dirmon_entry.pattern = "test/files/**/*.TxT"
          files                = []
          dirmon_entry.each do |file_name|
            files << file_name
          end
          assert_equal 1, files.count
          assert_equal IOStreams.path("test/files/text.txt").realpath, files.first
        end

        it "reads paths inside of the whitelist" do
          dirmon_entry.archive_directory = nil
          files                          = []
          dirmon_entry.stub(:whitelist_paths, [IOStreams.path("test/files").realpath.to_s]) do
            dirmon_entry.each do |file_name|
              files << file_name
            end
          end
          assert_nil dirmon_entry.archive_directory
          assert_equal 1, files.count
          assert_equal IOStreams.path("test/files/text.txt").realpath, files.first
        end

        it "skips paths outside of the whitelist" do
          dirmon_entry.archive_directory = nil
          files                          = []
          dirmon_entry.stub(:whitelist_paths, [IOStreams.path("test/config").realpath.to_s]) do
            dirmon_entry.each do |file_name|
              files << file_name
            end
          end
          assert_nil dirmon_entry.archive_directory
          assert_equal 0, files.count
        end
      end

      describe "#later" do
        it "enqueues job" do
          job = dirmon_entry.later(iopath)
          assert created_job = RocketJob::Jobs::UploadFileJob.last
          assert_equal job.id, created_job.id
          assert job.queued?
        end

        it "sets attributes" do
          job = dirmon_entry.later(iopath)

          upload_file_name = IOStreams.path(archive_directory).join("#{job.job_id}_#{File.basename(file_name)}").to_s

          assert_equal dirmon_entry.job_class_name, job.job_class_name
          assert_equal dirmon_entry.properties, job.properties
          assert_equal upload_file_name, job.upload_file_name
          assert_equal "#{dirmon_entry.name}: #{iopath.basename}", job.description
          assert_equal iopath.to_s, job.original_file_name
          assert job.job_id
        end
      end

      describe "#archive_iopath" do
        it "with fully qualified archive directory" do
          assert_equal archive_path.to_s, dirmon_entry.send(:archive_iopath, iopath).to_s
        end

        describe "with relative" do
          let :archive_directory do
            "my_archive/files"
          end

          it "archive directory" do
            archive_dir = iopath.directory.join(archive_directory)
            assert_equal archive_dir.to_s, dirmon_entry.send(:archive_iopath, iopath).to_s
          end
        end

        it "has a default archive directory" do
          e = RocketJob::DirmonEntry.new(
            pattern:        "test/files/**/*",
            job_class_name: "RocketJob::Jobs::DirmonJob"
          )
          assert_equal "archive", e.archive_directory
        end
      end
    end
  end
end

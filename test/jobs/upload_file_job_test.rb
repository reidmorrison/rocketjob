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

    # Reads the format of each file from the name of the file, such as `.csv`, which reads its header row.
    class AutoFormatJob < RocketJob::Job
      include RocketJob::Batch

      input_category format: :auto

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

      describe "#display_attributes" do
        it "shows the paths in the properties without their credentials" do
          batch_job.properties["input_categories"].first["file_name"] = "sftp://user:secret@sftp.example.org/in.csv"
          attrs = batch_job.display_attributes

          assert_equal "sftp://sftp.example.org/in.csv", attrs["properties"]["input_categories"].first["file_name"]
          assert_equal "sftp://user:secret@sftp.example.org/in.csv", batch_job.properties["input_categories"].first["file_name"]
        end

        it "shows the original file name without its credentials, such as one saved by Rocket Job 7.1" do
          job.original_file_name = "sftp://user:secret@sftp.example.org/in/data.csv"

          assert_includes RocketJob::Jobs::UploadFileJob.path_fields, :original_file_name
          assert_equal "sftp://sftp.example.org/in/data.csv", job.display_attributes["original_file_name"]
          assert_equal "sftp://user:secret@sftp.example.org/in/data.csv", job.original_file_name
        end

        it "shows the original file name that Dirmon records for a file whose display name leaves out part of its name" do
          job.original_file_name = "sftp://sftp.example.org/in/data%232026.csv.gz"

          assert_equal "sftp://sftp.example.org/in/data%232026.csv.gz", job.display_attributes["original_file_name"]
        end

        it "shows an original file name that is not a valid path as stored, when it holds no credentials" do
          job.original_file_name = "sftp://sftp.example.org/in/données[1].csv"

          assert_equal "sftp://sftp.example.org/in/données[1].csv", job.display_attributes["original_file_name"]
        end
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

        it "reads the streams of the file from the original file name that Dirmon records" do
          Dir.mktmpdir do |dir|
            # The archived file, without the extensions of the original file.
            upload_file_name = File.join(dir, "upload")
            FileUtils.cp(IOStreams.path("test", "batch", "files", "text.txt.gz").to_s, upload_file_name)
            batch_job.upload_file_name   = upload_file_name
            batch_job.original_file_name = "sftp://sftp.example.org/in/text%232026.txt.gz"
            batch_job.properties         = {}
            batch_job.perform_now
          end

          assert created_job = UploadFileJobTest::BatchTestJob.first
          assert_equal File.readlines("test/batch/files/text.txt", chomp: true), created_job.input.first.to_a
          assert_equal "sftp://sftp.example.org/in/text%232026.txt.gz", created_job.input_category.file_name.to_s
          assert_equal "/in/text#2026.txt.gz", created_job.input_category.file_name.path
        end

        describe "for a file that Dirmon finds on an SFTP server" do
          # A file that IOStreams.each_child finds on an SFTP server, which it names without percent-encoding it.
          def sftp_file(name)
            IOStreams.path("sftp://user:secret@sftp.example.org/in").send(:child_path, name)
          end

          # Returns [RocketJob::Jobs::AutoFormatJob] the job that the supplied UploadFileJob creates, read back from the
          # database, after running it.
          def upload(upload_job)
            upload_job.perform_now

            assert_predicate upload_job, :completed?, -> { upload_job.exception&.message }
            UploadFileJobTest::AutoFormatJob.find(UploadFileJobTest::AutoFormatJob.last.id)
          end

          [
            "données.csv.gz",
            "a b.csv.gz",
            "a+b.csv.gz",
            "100%.csv.gz",
            "a%20b.csv.gz",
            "data[1].csv.gz",
            "data#2026.csv.gz",
            "data?2026.csv.gz"
          ].each do |file_name|
            it "uploads the file by the extensions of its name, which IOStreams reads back: #{file_name}" do
              Dir.mktmpdir do |dir|
                entry = RocketJob::DirmonEntry.new(
                  name:              "Orders",
                  pattern:           "sftp://sftp.example.org/in/*",
                  job_class_name:    UploadFileJobTest::AutoFormatJob.name,
                  archive_directory: dir
                )
                file = sftp_file(file_name)
                file.define_singleton_method(:move_to) do |target|
                  target.stream(:gzip).write("first_name,last_name\nJack,Jones\n")
                  target
                end
                upload_job = entry.later(file)

                created_job = upload(RocketJob::Jobs::UploadFileJob.find(upload_job.id))

                assert_equal :csv, created_job.input_category.format
                assert_equal %w[first_name last_name], created_job.input_category.columns
                assert_equal ["Jack,Jones"], created_job.input.first.to_a
                assert_equal "/in/#{file_name}", created_job.input_category.file_name.path
              end
            end
          end

          it "uploads a file whose name is not valid UTF-8, by the name that Dirmon records" do
            Dir.mktmpdir do |dir|
              upload_file_name = File.join(dir, "upload")
              IOStreams.path(upload_file_name).stream(:gzip).write("first_name,last_name\nJack,Jones\n")
              upload_job = RocketJob::Jobs::UploadFileJob.create!(
                job_class_name:     UploadFileJobTest::AutoFormatJob.name,
                upload_file_name:   upload_file_name,
                original_file_name: RocketJob::DirmonEntry.new.file_display_name(sftp_file("caf\xE9.csv.gz".b))
              )

              created_job = upload(RocketJob::Jobs::UploadFileJob.find(upload_job.id))

              assert_equal "sftp://sftp.example.org/in/caf%E9.csv.gz", created_job.input_category.file_name.to_s
              assert_equal "/in/caf\xE9.csv.gz".b, created_job.input_category.file_name.path.b
              assert_equal ["Jack,Jones"], created_job.input.first.to_a
            end
          end

          it "uploads a file by the name that Rocket Job 7.1 recorded, which IOStreams cannot read as a url" do
            Dir.mktmpdir do |dir|
              upload_file_name = File.join(dir, "upload")
              IOStreams.path(upload_file_name).stream(:gzip).write("first_name,last_name\nJack,Jones\n")
              upload_job = RocketJob::Jobs::UploadFileJob.create!(
                job_class_name:     UploadFileJobTest::AutoFormatJob.name,
                upload_file_name:   upload_file_name,
                original_file_name: "sftp://sftp.example.org/in/données.csv.gz"
              )

              created_job = upload(RocketJob::Jobs::UploadFileJob.find(upload_job.id))

              assert_equal :csv, created_job.input_category.format
              assert_equal ["Jack,Jones"], created_job.input.first.to_a
              # Returned as stored, since IOStreams cannot build a path from it.
              assert_equal "sftp://sftp.example.org/in/données.csv.gz", created_job.input_category.file_name
            end
          end
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

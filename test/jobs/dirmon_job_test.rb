require_relative "../test_helper"

module Jobs
  class DirmonJobTest < Minitest::Test
    class TestJob < RocketJob::Job
      def perform
        3645
      end
    end

    describe RocketJob::Jobs::DirmonJob do
      include SemanticLogger::Test::Minitest

      let :dirmon_job do
        RocketJob::Jobs::DirmonJob.new
      end

      let :directory do
        "/tmp/directory"
      end

      let :archive_directory do
        "/tmp/archive_directory"
      end

      let :dirmon_entry do
        RocketJob::DirmonEntry.new(
          pattern:           "#{directory}/abc/*",
          job_class_name:    "Jobs::DirmonJobTest::TestJob",
          properties:        {priority: 23},
          archive_directory: archive_directory
        )
      end

      before do
        RocketJob::Jobs::DirmonJob.delete_all
        FileUtils.makedirs("#{directory}/abc")
      end

      after do
        IOStreams.path(archive_directory).delete_all
        IOStreams.path(directory).delete_all
      end

      describe "#check_file" do
        it "check growing file" do
          previous_size = 5
          new_size      = 10
          path          = create_temp_file(new_size)
          result        = dirmon_entry.stub(:later, nil) do
            dirmon_job.send(:check_file, dirmon_entry, path, previous_size)
          end

          assert_equal new_size, result
        end

        it "check completed file" do
          previous_size = 10
          new_size      = 10
          path          = create_temp_file(new_size)
          started       = false
          result        = dirmon_entry.stub(:later, ->(_fn) { started = true }) do
            dirmon_job.send(:check_file, dirmon_entry, path, previous_size)
          end

          assert_nil result
          assert started
        end

        it "skips a file that no longer exists" do
          started = false
          result  = dirmon_entry.stub(:later, ->(_fn) { started = true }) do
            dirmon_job.send(:check_file, dirmon_entry, IOStreams.path(directory, "abc", "removed"), 5)
          end

          assert_nil result
          refute started
        end

        it "skips a file that was removed from S3, SFTP or HTTP" do
          path      = IOStreams.path("https://example.org/files/removed.csv")
          not_found = IOStreams::Errors::NotFound.tag(
            IOStreams::Errors::CommunicationsFailure.new("404 Not Found"), path.display_name
          )
          result = path.stub(:size, -> { raise not_found }) do
            dirmon_job.send(:check_file, dirmon_entry, path, 5)
          end

          assert_nil result
        end

        it "raises any other failure" do
          path   = IOStreams.path("https://example.org/files/locked.csv")
          denied = IOStreams::Errors::PermissionDenied.tag(
            IOStreams::Errors::CommunicationsFailure.new("403 Forbidden"), path.display_name
          )

          path.stub(:size, -> { raise denied }) do
            assert_raises(IOStreams::Errors::PermissionDenied) do
              dirmon_job.send(:check_file, dirmon_entry, path, 5)
            end
          end
        end
      end

      describe "#check_entry" do
        let :unavailable do
          IOStreams::Errors::Unavailable.tag(Errno::ECONNREFUSED.new("sftp.example.org"), "sftp://sftp.example.org/abc")
        end

        before do
          RocketJob::DirmonEntry.destroy_all
          dirmon_entry.enable!
        end

        it "skips a file that was removed after it was found, without failing the entry" do
          removed    = IOStreams.path(directory, "abc", "removed")
          file_names = {}
          dirmon_entry.stub(:each, ->(&block) { block.call(removed) }) do
            dirmon_job.send(:check_entry, dirmon_entry, file_names)
          end

          assert_predicate dirmon_entry, :enabled?
          assert_empty file_names
        end

        it "keeps the entry enabled when its storage is unavailable" do
          dirmon_entry.stub(:each, -> { raise unavailable }) do
            dirmon_job.send(:check_entry, dirmon_entry, {})
          end
          dirmon_entry.reload

          assert_predicate dirmon_entry, :enabled?
          assert dirmon_entry.unavailable_at
        end

        it "fails the entry once its storage has been unavailable for longer than max_unavailable_seconds" do
          dirmon_entry.unavailable_at = Time.now - RocketJob::DirmonEntry.max_unavailable_seconds - 1
          dirmon_entry.save!
          dirmon_entry.stub(:each, -> { raise unavailable }) do
            dirmon_job.send(:check_entry, dirmon_entry, {})
          end
          dirmon_entry.reload

          assert_predicate dirmon_entry, :failed?
          assert_equal "Errno::ECONNREFUSED", dirmon_entry.exception.class_name
        end

        it "ends the outage once a scan succeeds" do
          dirmon_entry.unavailable_at = Time.now
          dirmon_entry.save!
          dirmon_entry.stub(:each, -> {}) do
            dirmon_job.send(:check_entry, dirmon_entry, {})
          end

          assert_predicate dirmon_entry.reload, :enabled?
          assert_nil dirmon_entry.unavailable_at
        end

        it "tracks and logs a file without the credentials in its url" do
          path       = IOStreams.path("sftp://jack:secret@sftp.example.org/abc/file.csv")
          file_names = {}
          events     = semantic_logger_events do
            path.stub(:size, 5) do
              dirmon_entry.stub(:each, ->(&block) { block.call(path) }) do
                dirmon_job.send(:check_entry, dirmon_entry, file_names)
              end
            end
          end

          assert_equal({"#{dirmon_entry.id}:sftp://sftp_example_org/abc/file_csv" => 5}, file_names)
          assert_includes events.map(&:message), "Found file: sftp://sftp.example.org/abc/file.csv. File size: 5"
          refute(events.any? { |event| "#{event.message}#{event.payload}".include?("secret") })
        end

        it "fails the entry on any other failure" do
          path   = IOStreams.path(directory, "abc", "locked")
          denied = IOStreams::Errors::PermissionDenied.tag(Errno::EACCES.new(path.to_s), path.display_name)
          path.stub(:size, -> { raise denied }) do
            dirmon_entry.stub(:each, ->(&block) { block.call(path) }) do
              dirmon_job.send(:check_entry, dirmon_entry, {})
            end
          end

          assert_predicate dirmon_entry.reload, :failed?
          assert_equal "Errno::EACCES", dirmon_entry.exception.class_name
        end
      end

      describe "#check_directories" do
        before do
          RocketJob::DirmonEntry.destroy_all
          dirmon_entry.enable!
        end

        it "no files" do
          result = dirmon_job.send(:check_directories)

          assert_equal 0, result.count
        end

        it "collect new files without enqueuing them" do
          create_file("#{directory}/abc/file1", 5)
          create_file("#{directory}/abc/file2", 10)

          result = dirmon_job.send(:check_directories)

          assert_equal [5, 10], result.values.sort
        end

        it "allow files to grow" do
          create_file("#{directory}/abc/file1", 5)
          create_file("#{directory}/abc/file2", 10)
          dirmon_job.send(:check_directories)
          create_file("#{directory}/abc/file1", 10)
          create_file("#{directory}/abc/file2", 15)
          result = dirmon_job.send(:check_directories)

          assert_equal [10, 15], result.values.sort
        end

        it "start all files" do
          create_file("#{directory}/abc/file1", 5)
          create_file("#{directory}/abc/file2", 10)
          files = dirmon_job.send(:check_directories)

          assert_equal 2, files.count, files
          assert_equal 2, dirmon_job.previous_file_names.count, files

          # files = dirmon_job.send(:check_directories)
          # assert_equal 0, files.count, files

          count  = 0
          result = RocketJob::DirmonEntry.stub_any_instance(:later, ->(_path) { count += 1 }) do
            dirmon_job.send(:check_directories)
          end

          assert_equal 0, result.count, result
          assert 2, count
        end

        it "skip files in archive directory" do
          dirmon_entry.archive_directory = "archive"
          dirmon_entry.pattern           = "#{directory}/abc/**/*"

          file_pathname = IOStreams.path(directory, "/abc/file1")
          create_file(file_pathname, 5)
          create_file("#{directory}/abc/file2", 10)

          archive_iopath = dirmon_entry.send(:archive_iopath, file_pathname)
          create_file("#{archive_iopath}/file3", 21)

          result = dirmon_job.send(:check_directories)

          assert_equal [5, 10], result.values.sort
        end
      end

      describe "#perform" do
        it "check directories and reschedule" do
          previous_file_names = {
            "#{directory}/abc/file1" => 5,
            "#{directory}/abc/file2" => 10
          }
          new_file_names = {
            "#{directory}/abc/file1" => 10,
            "#{directory}/abc/file2" => 10
          }

          assert_equal 0, RocketJob::Jobs::DirmonJob.count
          # perform_now does not save the job, just runs it
          dirmon_job = RocketJob::Jobs::DirmonJob.create!(
            previous_file_names: previous_file_names,
            priority:            11,
            cron_schedule:       "*/1 * * * * UTC"
          )
          RocketJob::Jobs::DirmonJob.stub_any_instance(:check_directories, new_file_names) do
            dirmon_job.perform_now
          end

          assert_predicate dirmon_job, :completed?, dirmon_job.status.inspect
          # Job must destroy on complete
          assert_equal 0, RocketJob::Jobs::DirmonJob.where(id: dirmon_job.id).count, -> { RocketJob::Jobs::DirmonJob.all.to_a.ai }

          # Must have enqueued another instance to run in the future
          assert_equal 1, RocketJob::Jobs::DirmonJob.count
          assert new_dirmon_job = RocketJob::Jobs::DirmonJob.last
          refute_equal dirmon_job.id.to_s, new_dirmon_job.id.to_s
          assert new_dirmon_job.run_at
          assert_equal 11, new_dirmon_job.priority
          assert_equal "*/1 * * * * UTC", new_dirmon_job.cron_schedule
          assert_predicate new_dirmon_job, :queued?

          new_dirmon_job.destroy
        end

        it "check directories and reschedule even on exception" do
          RocketJob::Jobs::DirmonJob.destroy_all
          # perform_now does not save the job, just runs it
          dirmon_job = RocketJob::Jobs::DirmonJob.create!(
            priority:            11,
            cron_schedule:       "*/1 * * * * UTC",
            destroy_on_complete: false
          )

          RocketJob::Jobs::DirmonJob.stub_any_instance(:check_directories, -> { raise "Oh no" }) do
            assert_raises RuntimeError do
              dirmon_job.perform_now
            end
          end
          dirmon_job.save!

          assert_predicate dirmon_job, :failed?, dirmon_job.status.ai
          assert_equal "RuntimeError", dirmon_job.exception.class_name, dirmon_job.exception.attributes
          assert_equal "Oh no", dirmon_job.exception.message, dirmon_job.exception.attributes

          # Must have enqueued another instance to run in the future
          assert_equal 2, RocketJob::Jobs::DirmonJob.count, -> { RocketJob::Jobs::DirmonJob.all.ai }
          assert new_dirmon_job = RocketJob::Jobs::DirmonJob.queued.first
          assert new_dirmon_job.run_at
          assert_equal 11, new_dirmon_job.priority, -> { new_dirmon_job.attributes.ai }
          assert_equal "*/1 * * * * UTC", new_dirmon_job.cron_schedule
          assert_predicate new_dirmon_job, :queued?, new_dirmon_job.state

          new_dirmon_job.destroy
        end
      end

      def create_file(file_name, size)
        IOStreams.new(file_name).write("*" * size)
      end

      def create_temp_file(size)
        path = IOStreams.path(directory, "abc", "check_file")
        create_file(path, size)

        assert_equal size, path.size
        path
      end
    end
  end
end

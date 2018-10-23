require_relative '../test_helper'

module Jobs
  class DirmonJobTest < Minitest::Test
    class TestJob < RocketJob::Job
      def perform
        3645
      end
    end

    describe RocketJob::Jobs::DirmonJob do
      let :dirmon_job do
        RocketJob::Jobs::DirmonJob.new
      end

      let :directory do
        '/tmp/directory'
      end

      let :archive_directory do
        '/tmp/archive_directory'
      end

      let :dirmon_entry do
        RocketJob::DirmonEntry.new(
          pattern:           "#{directory}/abc/*",
          job_class_name:    'Jobs::DirmonJobTest::TestJob',
          properties:        {priority: 23},
          archive_directory: archive_directory
        )
      end

      before do
        RocketJob::Jobs::DirmonJob.delete_all
        FileUtils.makedirs("#{directory}/abc")
      end

      after do
        FileUtils.remove_dir(archive_directory, true) if Dir.exist?(archive_directory)
        FileUtils.remove_dir(directory, true) if Dir.exist?(directory)
      end

      describe '#check_file' do
        it 'check growing file' do
          previous_size = 5
          new_size      = 10
          file          = create_temp_file(new_size)
          result        = dirmon_entry.stub(:later, nil) do
            dirmon_job.send(:check_file, dirmon_entry, file, previous_size)
          end
          assert_equal new_size, result
        end

        it 'check completed file' do
          previous_size = 10
          new_size      = 10
          file          = create_temp_file(new_size)
          started       = false
          result        = dirmon_entry.stub(:later, ->(_fn) { started = true }) do
            dirmon_job.send(:check_file, dirmon_entry, file, previous_size)
          end
          assert_nil result
          assert started
        end

        it 'check deleted file' do
          previous_size = 5
          file_name     = Pathname.new('blah')
          assert_raises Errno::ENOENT do
            dirmon_job.send(:check_file, dirmon_entry, file_name, previous_size)
          end
        end
      end

      describe '#check_directories' do
        before do
          RocketJob::DirmonEntry.destroy_all
          dirmon_entry.enable!
        end

        it 'no files' do
          result = dirmon_job.send(:check_directories)
          assert_equal 0, result.count
        end

        it 'collect new files without enqueuing them' do
          create_file("#{directory}/abc/file1", 5)
          create_file("#{directory}/abc/file2", 10)

          result = dirmon_job.send(:check_directories)
          assert_equal [5, 10], result.values.sort
        end

        it 'allow files to grow' do
          create_file("#{directory}/abc/file1", 5)
          create_file("#{directory}/abc/file2", 10)
          dirmon_job.send(:check_directories)
          create_file("#{directory}/abc/file1", 10)
          create_file("#{directory}/abc/file2", 15)
          result = dirmon_job.send(:check_directories)
          assert_equal [10, 15], result.values.sort
        end

        it 'start all files' do
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

        it 'skip files in archive directory' do
          dirmon_entry.archive_directory = 'archive'
          dirmon_entry.pattern           = "#{directory}/abc/**/*"

          file_pathname = Pathname.new("#{directory}/abc/file1")
          create_file(file_pathname.to_s, 5)
          create_file("#{directory}/abc/file2", 10)

          archive_pathname = dirmon_entry.send(:archive_pathname, file_pathname)
          create_file("#{archive_pathname}/file3", 21)

          result = dirmon_job.send(:check_directories)
          assert_equal [5, 10], result.values.sort
        end
      end

      describe '#perform' do
        it 'check directories and reschedule' do
          previous_file_names = {
            "#{directory}/abc/file1" => 5,
            "#{directory}/abc/file2" => 10
          }
          new_file_names      = {
            "#{directory}/abc/file1" => 10,
            "#{directory}/abc/file2" => 10
          }
          assert_equal 0, RocketJob::Jobs::DirmonJob.count
          # perform_now does not save the job, just runs it
          dirmon_job = RocketJob::Jobs::DirmonJob.create!(
            previous_file_names: previous_file_names,
            priority:            11,
            check_seconds:       30
          )
          RocketJob::Jobs::DirmonJob.stub_any_instance(:check_directories, new_file_names) do
            dirmon_job.perform_now
          end
          assert dirmon_job.completed?, dirmon_job.status.inspect
          # Job must destroy on complete
          assert_equal 0, RocketJob::Jobs::DirmonJob.where(id: dirmon_job.id).count, -> { RocketJob::Jobs::DirmonJob.all.to_a.ai }

          # Must have enqueued another instance to run in the future
          assert_equal 1, RocketJob::Jobs::DirmonJob.count
          assert new_dirmon_job = RocketJob::Jobs::DirmonJob.last
          refute_equal dirmon_job.id.to_s, new_dirmon_job.id.to_s
          assert new_dirmon_job.run_at
          assert_equal 11, new_dirmon_job.priority
          assert_equal 30, new_dirmon_job.check_seconds
          assert new_dirmon_job.queued?

          new_dirmon_job.destroy
        end

        it 'check directories and reschedule even on exception' do
          RocketJob::Jobs::DirmonJob.destroy_all
          # perform_now does not save the job, just runs it
          dirmon_job = RocketJob::Jobs::DirmonJob.create!(
            priority:            11,
            check_seconds:       30,
            destroy_on_complete: false
          )
          RocketJob::Jobs::DirmonJob.stub_any_instance(:check_directories, -> { raise 'Oh no' }) do
            assert_raises RuntimeError do
              dirmon_job.perform_now
            end
          end
          dirmon_job.save!
          assert dirmon_job.aborted?, dirmon_job.status.ai
          assert_equal 'RuntimeError', dirmon_job.exception.class_name, dirmon_job.exception.attributes
          assert_equal 'Oh no', dirmon_job.exception.message, dirmon_job.exception.attributes

          # Must have enqueued another instance to run in the future
          assert_equal 2, RocketJob::Jobs::DirmonJob.count, -> { RocketJob::Jobs::DirmonJob.all.ai }
          assert new_dirmon_job = RocketJob::Jobs::DirmonJob.queued.first
          assert new_dirmon_job.run_at
          assert_equal 11, new_dirmon_job.priority, -> { new_dirmon_job.attributes.ai }
          assert_equal 30, new_dirmon_job.check_seconds
          assert new_dirmon_job.queued?, new_dirmon_job.state

          new_dirmon_job.destroy
        end
      end

      def create_file(file_name, size)
        File.open(file_name, 'wb') { |file| file.write('*' * size) }
      end

      def create_temp_file(size)
        file      = Tempfile.new('check_file')
        file_name = file.path
        File.open(file_name, 'wb') { |f| f.write('*' * size) }
        assert_equal size, File.size(file_name)
        file
      end
    end
  end
end

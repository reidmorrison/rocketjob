require_relative 'test_helper'
require_relative 'jobs/test_job'

# Unit Test for RocketJob::Job
class DirmonJobTest < Minitest::Test
  describe RocketJob::Jobs::DirmonJob do
    before do
      @dirmon_job        = RocketJob::Jobs::DirmonJob.new
      @directory         = '/tmp/directory'
      @archive_directory = '/tmp/archive_directory'
      @entry             = RocketJob::DirmonEntry.new(
        pattern:           "#{@directory}/abc/*",
        job_class_name:    'Jobs::TestJob',
        arguments:         [{input: 'yes'}],
        properties:        {priority: 23, perform_method: :event},
        archive_directory: @archive_directory
      )
      FileUtils.makedirs("#{@directory}/abc")
      FileUtils.makedirs(@archive_directory)
    end

    after do
      @dirmon_job.destroy if @dirmon_job && !@dirmon_job.new_record?
      FileUtils.remove_dir(@archive_directory, true) if Dir.exist?(@archive_directory)
      FileUtils.remove_dir(@directory, true) if Dir.exist?(@directory)
    end

    describe '#check_file' do
      it 'check growing file' do
        previous_size = 5
        new_size      = 10
        file          = Tempfile.new('check_file')
        file_name     = file.path
        File.open(file_name, 'w') { |file| file.write('*' * new_size) }
        assert_equal new_size, File.size(file_name)
        result = @entry.stub(:later, nil) do
          @dirmon_job.send(:check_file, @entry, file, previous_size)
        end
        assert_equal new_size, result
      end

      it 'check completed file' do
        previous_size = 10
        new_size      = 10
        file          = Tempfile.new('check_file')
        file_name     = file.path
        File.open(file_name, 'w') { |file| file.write('*' * new_size) }
        assert_equal new_size, File.size(file_name)
        started = false
        result  = @entry.stub(:later, -> fn { started = true }) do
          @dirmon_job.send(:check_file, @entry, file, previous_size)
        end
        assert_equal nil, result
        assert started
      end

      it 'check deleted file' do
        previous_size = 5
        file_name     = Pathname.new('blah')
        result        = @dirmon_job.send(:check_file, @entry, file_name, previous_size)
        assert_equal nil, result
      end
    end

    describe '#check_directories' do
      before do
        RocketJob::DirmonEntry.destroy_all
        @entry.enable!
      end

      after do
        @entry.destroy if @entry
      end

      it 'no files' do
        previous_file_names = {}
        result              = @dirmon_job.send(:check_directories, previous_file_names)
        assert_equal 0, result.count
      end

      it 'collect new files without enqueuing them' do
        create_file("#{@directory}/abc/file1", 5)
        create_file("#{@directory}/abc/file2", 10)

        previous_file_names = {}
        result              = @dirmon_job.send(:check_directories, previous_file_names)
        assert_equal 2, result.count, result.inspect
        assert_equal 5, result.values.first, result.inspect
        assert_equal 10, result.values.second, result.inspect
      end

      it 'allow files to grow' do
        create_file("#{@directory}/abc/file1", 5)
        create_file("#{@directory}/abc/file2", 10)
        previous_file_names = {}
        @dirmon_job.send(:check_directories, previous_file_names)
        create_file("#{@directory}/abc/file1", 10)
        create_file("#{@directory}/abc/file2", 15)
        result = @dirmon_job.send(:check_directories, previous_file_names)
        assert_equal 2, result.count, result.inspect
        assert_equal 10, result.values.first, result.inspect
        assert_equal 15, result.values.second, result.inspect
      end

      it 'start all files' do
        create_file("#{@directory}/abc/file1", 5)
        create_file("#{@directory}/abc/file2", 10)
        previous_file_names = @dirmon_job.send(:check_directories, {})

        count  = 0
        result = RocketJob::DirmonEntry.stub_any_instance(:later, -> path { count += 1 }) do
          @dirmon_job.send(:check_directories, previous_file_names)
        end
        assert 2, count
        assert_equal 0, result.count, result.inspect
      end

      it 'skip files in archive directory' do
        @entry.archive_directory = nil
        @entry.pattern           = "#{@directory}/abc/**/*"

        create_file("#{@directory}/abc/file1", 5)
        create_file("#{@directory}/abc/file2", 10)
        FileUtils.makedirs("#{@directory}/abc/#{@entry.archive_pathname}")
        create_file("#{@directory}/abc/#{@entry.archive_pathname}/file3", 10)

        result = @dirmon_job.send(:check_directories, {})

        assert_equal 2, result.count, result.inspect
        assert_equal 5, result.values.first, result.inspect
        assert_equal 10, result.values.second, result.inspect
      end
    end

    describe '#perform' do
      it 'check directories and reschedule' do
        dirmon_job          = nil
        previous_file_names = {
          "#{@directory}/abc/file1" => 5,
          "#{@directory}/abc/file2" => 10,
        }
        new_file_names      = {
          "#{@directory}/abc/file1" => 10,
          "#{@directory}/abc/file2" => 10,
        }
        RocketJob::Jobs::DirmonJob.destroy_all
        RocketJob::Jobs::DirmonJob.stub_any_instance(:check_directories, new_file_names) do
          # perform_now does not save the job, just runs it
          dirmon_job = RocketJob::Jobs::DirmonJob.perform_now(previous_file_names) do |job|
            job.priority      = 11
            job.check_seconds = 30
          end
        end
        assert dirmon_job.completed?, dirmon_job.status.inspect

        # It it have enqueued another instance to run in the future
        assert_equal 1, RocketJob::Jobs::DirmonJob.count
        assert new_dirmon_job = RocketJob::Jobs::DirmonJob.last
        assert_equal false, dirmon_job.id == new_dirmon_job.id
        assert new_dirmon_job.run_at
        assert_equal 11, new_dirmon_job.priority
        assert_equal 30, new_dirmon_job.check_seconds
        assert new_dirmon_job.queued?

        new_dirmon_job.destroy
      end

      it 'check directories and reschedule even on exception' do
        dirmon_job = nil
        RocketJob::Jobs::DirmonJob.destroy_all
        RocketJob::Jobs::DirmonJob.stub_any_instance(:check_directories, -> previous { raise RuntimeError.new("Oh no") }) do
          # perform_now does not save the job, just runs it
          dirmon_job = RocketJob::Jobs::DirmonJob.perform_now do |job|
            job.priority      = 11
            job.check_seconds = 30
          end
        end
        assert dirmon_job.failed?, dirmon_job.status.inspect

        # It it have enqueued another instance to run in the future
        assert_equal 2, RocketJob::Jobs::DirmonJob.count
        assert new_dirmon_job = RocketJob::Jobs::DirmonJob.last
        assert new_dirmon_job.run_at
        assert_equal 11, new_dirmon_job.priority
        assert_equal 30, new_dirmon_job.check_seconds
        assert new_dirmon_job.queued?

        new_dirmon_job.destroy
      end
    end

    def create_file(file_name, size)
      File.open(file_name, 'w') { |file| file.write('*' * size) }
    end
  end
end

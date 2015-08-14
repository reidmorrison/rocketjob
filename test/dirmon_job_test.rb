require_relative 'test_helper'
require_relative 'jobs/test_job'

# Unit Test for RocketJob::Job
class DirmonJobTest < Minitest::Test
  context RocketJob::Jobs::DirmonJob do
    setup do
      @worker = RocketJob::Worker.new
      @worker.started
      @dirmon_job        = RocketJob::Jobs::DirmonJob.new
      @archive_directory = '/tmp/archive_directory'
      @entry             = RocketJob::DirmonEntry.new(
        pattern:           'abc/*',
        job_class_name:    'Jobs::TestJob',
        arguments:         [{input: 'yes'}],
        properties:        {priority: 23, perform_method: :event},
        archive_directory: @archive_directory
      )
      @job               = Jobs::TestJob.new
      @patterns          = {
        'abc/*' => %w(abc/file1 abc/file2)
      }
    end

    teardown do
      @dirmon_job.destroy if @dirmon_job && !@dirmon_job.new_record?
      FileUtils.remove_dir(@archive_directory, true) if Dir.exist?(@archive_directory)
    end

    context '#check_file' do
      should 'check growing file' do
        previous_size = 5
        new_size      = 10
        file          = Tempfile.new('check_file')
        file_name     = file.path
        File.open(file_name, 'w') { |file| file.write('*' * new_size) }
        assert_equal new_size, File.size(file_name)
        result = @dirmon_job.check_file(@entry, file_name, previous_size)
        assert_equal new_size, result
      end

      should 'check completed file' do
        previous_size = 10
        new_size      = 10
        file          = Tempfile.new('check_file')
        file_name     = file.path
        File.open(file_name, 'w') { |file| file.write('*' * new_size) }
        assert_equal new_size, File.size(file_name)
        started = false
        result  = @dirmon_job.stub(:start_job, -> e, fn { started = true }) do
          @dirmon_job.check_file(@entry, file_name, previous_size)
        end
        assert_equal nil, result
        assert started
      end

      should 'check deleted file' do
        previous_size = 5
        file_name     = 'blah'
        result        = @dirmon_job.check_file(@entry, file_name, previous_size)
        assert_equal nil, result
      end
    end

    context '#check_directories' do
      setup do
        @entry.save!
      end

      teardown do
        @entry.destroy if @entry
      end

      should 'no files' do
        previous_file_names = {}
        result              = nil
        Dir.stub(:[], -> dir { [] }) do
          result = @dirmon_job.check_directories(previous_file_names)
        end
        assert_equal 0, result.count
      end

      should 'new files' do
        previous_file_names = {}
        result              = nil
        Dir.stub(:[], -> dir { @patterns[dir] }) do
          result = @dirmon_job.stub(:check_file, -> e, fn, ps { 5 }) do
            @dirmon_job.check_directories(previous_file_names)
          end
        end
        assert_equal result.count, @patterns['abc/*'].count
        result.each_pair do |k, v|
          assert_equal 5, v
        end
      end

      should 'allow files to grow' do
        previous_file_names = {}
        @patterns['abc/*'].each { |file_name| previous_file_names[file_name] = 5 }
        result = nil
        Dir.stub(:[], -> dir { @patterns[dir] }) do
          result = @dirmon_job.stub(:check_file, -> e, fn, ps { 10 }) do
            @dirmon_job.check_directories(previous_file_names)
          end
        end
        assert_equal result.count, @patterns['abc/*'].count
        result.each_pair do |k, v|
          assert_equal 10, v
        end
      end

      should 'start all files' do
        previous_file_names = {}
        @patterns['abc/*'].each { |file_name| previous_file_names[file_name] = 10 }
        result = nil
        Dir.stub(:[], -> dir { @patterns[dir] }) do
          result = @dirmon_job.stub(:check_file, -> e, fn, ps { nil }) do
            @dirmon_job.check_directories(previous_file_names)
          end
        end
        assert_equal 0, result.count
      end

      should 'skip files in archive directory' do
        previous_file_names = {}
        @patterns['abc/*'].each { |file_name| previous_file_names[file_name] = 5 }
        result = nil
        # Add a file in the archive directory
        @patterns['abc/*'] << File.join('abc', RocketJob::Jobs::DirmonJob::DEFAULT_ARCHIVE_DIR, 'test.zip')
        Dir.stub(:[], -> dir { @patterns[dir] }) do
          result = @dirmon_job.stub(:check_file, -> e, fn, ps { 10 }) do
            @dirmon_job.check_directories(previous_file_names)
          end
        end
        assert_equal result.count, @patterns['abc/*'].count - 1
        result.each_pair do |k, v|
          assert_equal 10, v
        end
      end
    end

    context '#perform' do
      should 'check directories and reschedule' do
        dirmon_job          = nil
        previous_file_names = {}
        @patterns['abc/*'].each { |file_name| previous_file_names[file_name] = 5 }
        new_file_names = {}
        @patterns['abc/*'].each { |file_name| new_file_names[file_name] = 10 }
        RocketJob::Jobs::DirmonJob.destroy_all
        RocketJob::Jobs::DirmonJob.stub_any_instance(:check_directories, new_file_names) do
          # perform_now does not save the job, just runs it
          dirmon_job = RocketJob::Jobs::DirmonJob.perform_now(previous_file_names) do |job|
            job.priority      = 11
            job.check_seconds = 30
          end
        end
        assert dirmon_job.completed?, dirmon_job.status.inspect

        # It should have enqueued another instance to run in the future
        assert_equal 1, RocketJob::Jobs::DirmonJob.count
        assert new_dirmon_job = RocketJob::Jobs::DirmonJob.last
        assert_equal false, dirmon_job.id == new_dirmon_job.id
        assert new_dirmon_job.run_at
        assert_equal 11, new_dirmon_job.priority
        assert_equal 30, new_dirmon_job.check_seconds
        assert new_dirmon_job.queued?

        new_dirmon_job.destroy
      end

      should 'check directories and reschedule even on exception' do
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

        # It should have enqueued another instance to run in the future
        assert_equal 2, RocketJob::Jobs::DirmonJob.count
        assert new_dirmon_job = RocketJob::Jobs::DirmonJob.last
        assert new_dirmon_job.run_at
        assert_equal 11, new_dirmon_job.priority
        assert_equal 30, new_dirmon_job.check_seconds
        assert new_dirmon_job.queued?

        new_dirmon_job.destroy
      end
    end

  end
end

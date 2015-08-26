require_relative 'test_helper'
require_relative 'jobs/test_job'

# Unit Test for RocketJob::Job
class DirmonEntryTest < Minitest::Test
  context RocketJob::DirmonEntry do
    context '.config' do
      should 'support multiple databases' do
        assert_equal 'test_rocketjob', RocketJob::DirmonEntry.collection.db.name
      end
    end

    context '#job_class' do
      context 'with a nil job_class_name' do
        should 'return nil' do
          entry = RocketJob::DirmonEntry.new
          assert_equal(nil, entry.job_class)
        end
      end

      context 'with an unknown job_class_name' do
        should 'return nil' do
          entry = RocketJob::DirmonEntry.new(job_class_name: 'FakeJobThatDoesNotExistAnyWhereIPromise')
          assert_equal(nil, entry.job_class)
        end
      end

      context 'with a valid job_class_name' do
        should 'return job class' do
          entry = RocketJob::DirmonEntry.new(job_class_name: 'RocketJob::Job')
          assert_equal(RocketJob::Job, entry.job_class)
        end
      end
    end

    context '.whitelist_paths' do
      should 'default to []' do
        assert_equal [], RocketJob::DirmonEntry.whitelist_paths
      end
    end

    context '.add_whitelist_path' do
      teardown do
        RocketJob::DirmonEntry.whitelist_paths.each { |path| RocketJob::DirmonEntry.delete_whitelist_path(path) }
      end

      should 'convert relative path to an absolute one' do
        path = Pathname('test/jobs').realpath.to_s
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path('test/jobs')
        assert_equal [path], RocketJob::DirmonEntry.whitelist_paths
      end

      should 'prevent duplicates' do
        path = Pathname('test/jobs').realpath.to_s
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path('test/jobs')
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path('test/jobs')
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path(path)
        assert_equal [path], RocketJob::DirmonEntry.whitelist_paths
      end
    end

    context '#fail_with_exception!' do
      setup do
        @dirmon_entry = RocketJob::DirmonEntry.new(job_class_name: 'Jobs::TestJob', pattern: '/abc/**', arguments: [1])
        @dirmon_entry.enable!
      end
      teardown do
        @dirmon_entry.destroy if @dirmon_entry && @dirmon_entry.new_record?
      end

      should 'fail with message' do
        @dirmon_entry.fail_with_exception!('myworker:2323', 'oh no')
        assert_equal true, @dirmon_entry.failed?
        assert_equal 'RocketJob::DirmonEntryException', @dirmon_entry.exception.class_name
        assert_equal 'oh no', @dirmon_entry.exception.message
      end

      should 'fail with exception' do
        exception = nil
        begin
          blah
        rescue Exception => exc
          exception = exc
        end
        @dirmon_entry.fail_with_exception!('myworker:2323', exception)

        assert_equal true, @dirmon_entry.failed?
        assert_equal exception.class.name.to_s, @dirmon_entry.exception.class_name
        assert @dirmon_entry.exception.message.include?('undefined local variable or method'), @dirmon_entry.attributes.inspect
      end
    end

    context '#validate' do
      should 'existance' do
        assert entry = RocketJob::DirmonEntry.new(job_class_name: 'Jobs::TestJob')
        assert_equal false, entry.valid?
        assert_equal ["can't be blank"], entry.errors[:pattern], entry.errors.inspect
      end

      context 'job_class_name' do
        should 'ensure presence' do
          assert entry = RocketJob::DirmonEntry.new(pattern: '/abc/**')
          assert_equal false, entry.valid?
          assert_equal ["can't be blank", 'job_class_name must be defined and must be derived from RocketJob::Job'], entry.errors[:job_class_name], entry.errors.inspect
        end
      end

      context 'arguments' do
        should 'allow no arguments' do
          assert entry = RocketJob::DirmonEntry.new(
              job_class_name: 'Jobs::TestJob',
              pattern:        '/abc/**',
              perform_method: :result
            )
          assert_equal true, entry.valid?, entry.errors.inspect
          assert_equal [], entry.errors[:arguments], entry.errors.inspect
        end

        should 'ensure correct number of arguments' do
          assert entry = RocketJob::DirmonEntry.new(
              job_class_name: 'Jobs::TestJob',
              pattern:        '/abc/**'
            )
          assert_equal false, entry.valid?
          assert_equal ['There must be 1 argument(s)'], entry.errors[:arguments], entry.errors.inspect
        end

        should 'return false if the job name is bad' do
          assert entry = RocketJob::DirmonEntry.new(
              job_class_name: 'Jobs::Tests::Names::Things',
              pattern:        '/abc/**'
            )
          assert_equal false, entry.valid?
          assert_equal [], entry.errors[:arguments], entry.errors.inspect
        end
      end

      should 'arguments with perform_method' do
        assert entry = RocketJob::DirmonEntry.new(
            job_class_name: 'Jobs::TestJob',
            pattern:        '/abc/**',
            perform_method: :sum
          )
        assert_equal false, entry.valid?
        assert_equal ['There must be 2 argument(s)'], entry.errors[:arguments], entry.errors.inspect
      end

      should 'valid' do
        assert entry = RocketJob::DirmonEntry.new(
            job_class_name: 'Jobs::TestJob',
            pattern:        '/abc/**',
            arguments:      [1]
          )
        assert entry.valid?, entry.errors.inspect
      end

      should 'valid with perform_method' do
        assert entry = RocketJob::DirmonEntry.new(
            job_class_name: 'Jobs::TestJob',
            pattern:        '/abc/**',
            perform_method: :sum,
            arguments:      [1, 2]
          )
        assert entry.valid?, entry.errors.inspect
      end
    end

    context 'with valid entry' do
      setup do
        @archive_directory = '/tmp/archive_directory'
        @entry             = RocketJob::DirmonEntry.new(
          pattern:           'abc/*',
          job_class_name:    'Jobs::TestJob',
          arguments:         [{input: 'yes'}],
          properties:        {priority: 23, perform_method: :event},
          archive_directory: @archive_directory
        )
        @job               = Jobs::TestJob.new
        @file              = Tempfile.new('archive')
        @file_name         = @file.path
        @pathname          = Pathname.new(@file_name)
        File.open(@file_name, 'w') { |file| file.write('Hello World') }
        assert File.exists?(@file_name)
        @archive_file_name = File.join(@archive_directory, "#{@job.id}_#{File.basename(@file_name)}")
      end

      teardown do
        @file.delete if @file
      end

      context '#archive_pathname' do
        should 'with archive directory' do
          assert_equal @archive_directory.to_s, @entry.archive_pathname.to_s
        end

        should 'without archive directory' do
          @entry.archive_directory = nil
          assert_equal '_archive', @entry.archive_pathname.to_s
        end
      end

      context '#archive_file' do
        should 'archive file' do
          assert_equal @archive_file_name, @entry.send(:archive_file, @job, Pathname.new(@file_name))
          assert File.exists?(@archive_file_name), @archive_file_name
        end
      end

      context '#upload_default' do
        should 'upload' do
          @entry.send(:upload_default, @job, @pathname)
          assert_equal File.absolute_path(@archive_file_name), @job.arguments.first[:full_file_name], @job.arguments
        end
      end

      context '#upload_file' do
        should 'upload using #file_store_upload' do
          @job.define_singleton_method(:file_store_upload) do |file_name|
            self.description = "FILE:#{file_name}"
          end
          @entry.send(:upload_file, @job, @pathname)
          assert_equal "FILE:#{@file_name}", @job.description
        end

        should 'upload using #upload' do
          @job.define_singleton_method(:upload) do |file_name|
            self.description = "FILE:#{file_name}"
          end
          @entry.send(:upload_file, @job, @pathname)
          assert_equal "FILE:#{@file_name}", @job.description
        end
      end

      context '#later' do
        should 'enqueue job' do
          @entry.arguments = [{}]
          @entry.perform_method = :event
          job = @entry.later(@pathname)
          assert_equal File.join(@archive_directory, "#{job.id}_#{File.basename(@file_name)}"), job.arguments.first[:full_file_name]
          assert job.queued?
        end
      end
    end

  end
end

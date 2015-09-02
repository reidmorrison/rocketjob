require_relative 'test_helper'
require_relative 'jobs/test_job'

# Unit Test for RocketJob::Job
class DirmonEntryTest < Minitest::Test
  describe RocketJob::DirmonEntry do
    describe '.config' do
      it 'support multiple databases' do
        assert_equal 'test_rocketjob', RocketJob::DirmonEntry.collection.db.name
      end
    end

    describe '#job_class' do
      describe 'with a nil job_class_name' do
        it 'return nil' do
          entry = RocketJob::DirmonEntry.new
          assert_equal(nil, entry.job_class)
        end
      end

      describe 'with an unknown job_class_name' do
        it 'return nil' do
          entry = RocketJob::DirmonEntry.new(job_class_name: 'FakeJobThatDoesNotExistAnyWhereIPromise')
          assert_equal(nil, entry.job_class)
        end
      end

      describe 'with a valid job_class_name' do
        it 'return job class' do
          entry = RocketJob::DirmonEntry.new(job_class_name: 'RocketJob::Job')
          assert_equal(RocketJob::Job, entry.job_class)
          assert_equal 0, entry.arguments.size
          assert_equal 0, entry.properties.size
        end
      end
    end

    describe '.whitelist_paths' do
      it 'default to []' do
        assert_equal [], RocketJob::DirmonEntry.whitelist_paths
      end
    end

    describe '.add_whitelist_path' do
      after do
        RocketJob::DirmonEntry.whitelist_paths.each { |path| RocketJob::DirmonEntry.delete_whitelist_path(path) }
      end

      it 'convert relative path to an absolute one' do
        path = Pathname('test/jobs').realpath.to_s
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path('test/jobs')
        assert_equal [path], RocketJob::DirmonEntry.whitelist_paths
      end

      it 'prevent duplicates' do
        path = Pathname('test/jobs').realpath.to_s
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path('test/jobs')
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path('test/jobs')
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path(path)
        assert_equal [path], RocketJob::DirmonEntry.whitelist_paths
      end
    end

    describe '#fail_with_exception!' do
      before do
        @dirmon_entry = RocketJob::DirmonEntry.new(job_class_name: 'Jobs::TestJob', pattern: '/abc/**', arguments: [1])
        @dirmon_entry.enable!
      end
      after do
        @dirmon_entry.destroy if @dirmon_entry && @dirmon_entry.new_record?
      end

      it 'fail with message' do
        @dirmon_entry.fail_with_exception!('myworker:2323', 'oh no')
        assert_equal true, @dirmon_entry.failed?
        assert_equal 'RocketJob::DirmonEntryException', @dirmon_entry.exception.class_name
        assert_equal 'oh no', @dirmon_entry.exception.message
      end

      it 'fail with exception' do
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

    describe '#validate' do
      it 'existance' do
        assert entry = RocketJob::DirmonEntry.new(job_class_name: 'Jobs::TestJob')
        assert_equal false, entry.valid?
        assert_equal ["can't be blank"], entry.errors[:pattern], entry.errors.inspect
      end

      describe 'perform_method' do
        describe 'with an invalid method' do
          it 'add errors to the entry' do
            entry = RocketJob::DirmonEntry.new(job_class_name: 'Jobs::TestJob', perform_method: :missing_perform_method)
            assert_equal false, entry.valid?
            assert_equal ['Method not implemented by Jobs::TestJob'], entry.errors[:perform_method], entry.errors.inspect
          end
        end
      end

      describe 'job_class_name' do
        it 'ensure presence' do
          assert entry = RocketJob::DirmonEntry.new(pattern: '/abc/**')
          assert_equal false, entry.valid?
          assert_equal ["can't be blank", 'job_class_name must be defined and must be derived from RocketJob::Job'], entry.errors[:job_class_name], entry.errors.inspect
        end
      end

      describe 'arguments' do
        it 'allow no arguments' do
          assert entry = RocketJob::DirmonEntry.new(
              job_class_name: 'Jobs::TestJob',
              pattern:        '/abc/**',
              perform_method: :result
            )
          assert_equal true, entry.valid?, entry.errors.inspect
          assert_equal [], entry.errors[:arguments], entry.errors.inspect
        end

        it 'ensure correct number of arguments' do
          assert entry = RocketJob::DirmonEntry.new(
              job_class_name: 'Jobs::TestJob',
              pattern:        '/abc/**'
            )
          assert_equal false, entry.valid?
          assert_equal ['There must be 1 argument(s)'], entry.errors[:arguments], entry.errors.inspect
        end

        it 'return false if the job name is bad' do
          assert entry = RocketJob::DirmonEntry.new(
              job_class_name: 'Jobs::Tests::Names::Things',
              pattern:        '/abc/**'
            )
          assert_equal false, entry.valid?
          assert_equal [], entry.errors[:arguments], entry.errors.inspect
        end
      end

      it 'arguments with perform_method' do
        assert entry = RocketJob::DirmonEntry.new(
            job_class_name: 'Jobs::TestJob',
            pattern:        '/abc/**',
            perform_method: :sum
          )
        assert_equal false, entry.valid?
        assert_equal ['There must be 2 argument(s)'], entry.errors[:arguments], entry.errors.inspect
      end

      it 'valid' do
        assert entry = RocketJob::DirmonEntry.new(
            job_class_name: 'Jobs::TestJob',
            pattern:        '/abc/**',
            arguments:      [1]
          )
        assert entry.valid?, entry.errors.inspect
      end

      it 'valid with perform_method' do
        assert entry = RocketJob::DirmonEntry.new(
            job_class_name: 'Jobs::TestJob',
            pattern:        '/abc/**',
            perform_method: :sum,
            arguments:      [1, 2]
          )
        assert entry.valid?, entry.errors.inspect
      end
    end

    describe 'with valid entry' do
      before do
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

      after do
        @file.delete if @file
      end

      describe '#archive_pathname' do
        it 'with archive directory' do
          assert_equal @archive_directory.to_s, @entry.archive_pathname.to_s
        end

        it 'without archive directory' do
          @entry.archive_directory = nil
          assert_equal '_archive', @entry.archive_pathname.to_s
        end
      end

      describe '#archive_file' do
        it 'archive file' do
          assert_equal @archive_file_name, @entry.send(:archive_file, @job, Pathname.new(@file_name))
          assert File.exists?(@archive_file_name), @archive_file_name
        end
      end

      describe '#upload_default' do
        it 'upload' do
          @entry.send(:upload_default, @job, @pathname)
          assert_equal File.absolute_path(@archive_file_name), @job.arguments.first[:full_file_name], @job.arguments
        end
      end

      describe '#upload_file' do
        it 'upload using #file_store_upload' do
          @job.define_singleton_method(:file_store_upload) do |file_name|
            self.description = "FILE:#{file_name}"
          end
          @entry.send(:upload_file, @job, @pathname)
          assert_equal "FILE:#{@file_name}", @job.description
        end

        it 'upload using #upload' do
          @job.define_singleton_method(:upload) do |file_name|
            self.description = "FILE:#{file_name}"
          end
          @entry.send(:upload_file, @job, @pathname)
          assert_equal "FILE:#{@file_name}", @job.description
        end
      end

      describe '#later' do
        it 'enqueue job' do
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

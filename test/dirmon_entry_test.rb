require_relative 'test_helper'

# Unit Test for RocketJob::Job
class DirmonEntryTest < Minitest::Test

  class OneArgumentJob < RocketJob::Job
    def perform(arg)
    end
  end

  class WithFullFileNameJob < RocketJob::Job
    # Dirmon will store the filename in this property when starting the job
    field :upload_file_name, type: String

    def perform
      # Do something with the file name stored in :upload_file_name
    end
  end

  class SumJob < RocketJob::Job
    @@result = nil

    # For temp test data
    def self.result
      @@result
    end

    def perform(a, b)
      @@result = a + b
    end
  end

  describe RocketJob::DirmonEntry do
    describe '.config' do
      it 'support multiple databases' do
        assert_equal 'rocketjob_test', RocketJob::DirmonEntry.collection.database.name
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
        path = Pathname('test/files').realpath.to_s
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path('test/files')
        assert_equal [path], RocketJob::DirmonEntry.whitelist_paths
      end

      it 'prevent duplicates' do
        path = Pathname('test/files').realpath.to_s
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path('test/files')
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path('test/files')
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path(path)
        assert_equal [path], RocketJob::DirmonEntry.whitelist_paths
      end
    end

    describe '#fail!' do
      before do
        @dirmon_entry = RocketJob::DirmonEntry.new(job_class_name: 'DirmonEntryTest::OneArgumentJob', pattern: 'test/files/**', arguments: [1])
        @dirmon_entry.enable!
        assert @dirmon_entry.valid?, @dirmon_entry.errors.messages.ai
      end

      after do
        @dirmon_entry.destroy if @dirmon_entry && @dirmon_entry.new_record?
      end

      it 'fail with message' do
        @dirmon_entry.fail!('myworker:2323', 'oh no')
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
        @dirmon_entry.fail!('myworker:2323', exception)

        assert_equal true, @dirmon_entry.failed?
        assert_equal exception.class.name.to_s, @dirmon_entry.exception.class_name
        assert @dirmon_entry.exception.message.include?('undefined local variable or method'), @dirmon_entry.attributes.inspect
      end
    end

    describe '#validate' do
      it 'existance' do
        assert entry = RocketJob::DirmonEntry.new(job_class_name: 'DirmonEntryTest::OneArgumentJob')
        assert_equal false, entry.valid?
        assert_equal ["can't be blank"], entry.errors[:pattern], entry.errors.messages.ai
      end

      describe 'job_class_name' do
        it 'ensure presence' do
          assert entry = RocketJob::DirmonEntry.new(pattern: 'test/files/**')
          assert_equal false, entry.valid?
          assert_equal ["can't be blank", 'job_class_name must be defined and must be derived from RocketJob::Job'], entry.errors[:job_class_name], entry.errors.messages.ai
        end
      end

      describe 'arguments' do
        it 'allow no arguments' do
          assert entry = RocketJob::DirmonEntry.new(
            job_class_name: 'DirmonEntryTest::WithFullFileNameJob',
            pattern:        'test/files/**'
          )
          assert entry.valid?, entry.errors.messages.ai
        end

        it 'ensure correct number of arguments' do
          assert entry = RocketJob::DirmonEntry.new(
            job_class_name: 'DirmonEntryTest::OneArgumentJob',
            pattern:        'test/files/**'
          )
          refute entry.valid?
          assert_equal ['There must be 1 argument(s)'], entry.errors[:arguments], entry.errors.messages.ai
        end

        it 'fail if the job name is bad' do
          assert entry = RocketJob::DirmonEntry.new(
            job_class_name: 'Jobs::Tests::Names::Things',
            pattern:        'test/files/**'
          )
          refute entry.valid?
          assert_equal [], entry.errors[:arguments], entry.errors.messages.ai
        end
      end

      it 'invalid without 2 arguments' do
        assert entry = RocketJob::DirmonEntry.new(
          job_class_name: 'DirmonEntryTest::SumJob',
          pattern:        'test/files/**'
        )
        refute entry.valid?
        assert_equal ['There must be 2 argument(s)'], entry.errors[:arguments], entry.errors.messages.ai
      end

      it 'valid with 2 arguments' do
        assert entry = RocketJob::DirmonEntry.new(
          job_class_name: 'DirmonEntryTest::SumJob',
          pattern:        'test/files/**',
          arguments:      [1, 2]
        )
        assert entry.valid?, entry.errors.messages.ai
      end
    end

    describe 'with valid entry' do
      before do
        RocketJob::Jobs::DirmonJob.delete_all
        @archive_directory = '/tmp/archive_directory'
        @archive_path      = Pathname.new(@archive_directory)
        @archive_path.mkpath
        @archive_path = @archive_path.realdirpath
        @entry        = RocketJob::DirmonEntry.new(
          pattern:           'test/files/**/*',
          job_class_name:    'RocketJob::Jobs::DirmonJob',
          arguments:         [{}],
          properties:        {priority: 23},
          archive_directory: @archive_directory
        )
        @job          = DirmonEntryTest::OneArgumentJob.new(
          @entry.properties.merge(arguments: @entry.arguments)
        )
        @file         = Tempfile.new('archive')
        @file_name    = @file.path
        @pathname     = Pathname.new(@file_name)
        File.open(@file_name, 'w') { |file| file.write('Hello World') }
        assert File.exist?(@file_name)
        @archive_real_name = @archive_path.join("#{@job.id}_#{File.basename(@file_name)}").to_s
      end

      after do
        @file.delete if @file
        RocketJob::Jobs::DirmonJob.delete_all
      end

      describe '#archive_pathname' do
        it 'with archive directory' do
          assert_equal File.dirname(@archive_real_name), @entry.archive_pathname(@pathname).to_s
        end

        it 'without archive directory' do
          @entry.archive_directory = nil
          assert @entry.archive_pathname(@pathname).to_s.end_with?('_archive')
        end
      end

      describe '#archive_file' do
        it 'archive file' do
          assert_equal @archive_real_name, @entry.send(:archive_file, @job, Pathname.new(@file_name))
          assert File.exist?(@archive_real_name)
        end
      end

      describe '#upload_default' do
        it 'sets full_file_name in Hash argument' do
          @entry.send(:upload_default, @job, @pathname)
          assert_equal @archive_real_name, @job.arguments.first[:full_file_name], @job.arguments
        end

        it 'sets upload_file_name property' do
          @entry = RocketJob::DirmonEntry.new(
            pattern:           'test/files/**/*',
            job_class_name:    'DirmonEntryTest::WithFullFileNameJob',
            archive_directory: @archive_directory
          )
          assert @entry.valid?, @entry.errors.messages
          job = @entry.job_class.new
          @entry.send(:upload_default, job, @pathname)
          archive_real_name = @archive_path.join("#{job.id}_#{File.basename(@file_name)}").to_s
          assert_equal archive_real_name, job.upload_file_name, job.arguments
        end

        it 'handles non hash argument and missing property' do
          @job.arguments = [1]
          assert_raises ArgumentError do
            @entry.send(:upload_default, @job, @pathname)
          end
        end
      end

      describe '#upload_file' do
        it 'upload using #upload' do
          @job.define_singleton_method(:upload) do |file_name|
            self.description = "FILE:#{file_name}"
          end
          @entry.send(:upload_file, @job, @pathname)
          assert_equal "FILE:#{@file_name}", @job.description
        end
      end

      describe '#later' do
        it 'enqueues job' do
          @entry.arguments = [{}]
          job              = @entry.later(@pathname)
          assert_equal Pathname.new(@archive_directory).join("#{job.id}_#{File.basename(@file_name)}").realdirpath.to_s, job.arguments.first[:full_file_name]
          assert job.queued?
          assert_equal 23, job.priority
        end

        it 'fails with bad job class name' do
          @entry.arguments      = [{}]
          @entry.job_class_name = 'Blah'
          assert_raises ArgumentError do
            @entry.later(@pathname)
          end
        end
      end

      describe '#each' do
        it 'without archive path' do
          @entry.archive_directory = nil
          files                    = []
          @entry.each do |file_name|
            files << file_name
          end
          assert_equal nil, @entry.archive_directory
          assert_equal 1, files.count
          assert_equal Pathname.new('test/files/text.txt').realpath, files.first
        end

        it 'with archive path' do
          files = []
          @entry.each do |file_name|
            files << file_name
          end
          assert_equal 1, files.count
          assert_equal Pathname.new('test/files/text.txt').realpath, files.first
        end

        it 'with case-insensitive pattern' do
          @entry.pattern = 'test/files/**/*.TxT'
          files          = []
          @entry.each do |file_name|
            files << file_name
          end
          assert_equal 1, files.count
          assert_equal Pathname.new('test/files/text.txt').realpath, files.first
        end

        it 'reads paths inside of the whitelist' do
          @entry.archive_directory = nil
          files                    = []
          @entry.stub(:whitelist_paths, [Pathname.new('test/files').realpath.to_s]) do
            @entry.each do |file_name|
              files << file_name
            end
          end
          assert_equal nil, @entry.archive_directory
          assert_equal 1, files.count
          assert_equal Pathname.new('test/files/text.txt').realpath, files.first
        end

        it 'skips paths outside of the whitelist' do
          @entry.archive_directory = nil
          files                    = []
          @entry.stub(:whitelist_paths, [Pathname.new('test/config').realpath.to_s]) do
            @entry.each do |file_name|
              files << file_name
            end
          end
          assert_equal nil, @entry.archive_directory
          assert_equal 0, files.count
        end
      end
    end

  end
end

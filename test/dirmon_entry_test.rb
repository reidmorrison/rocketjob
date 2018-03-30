require_relative 'test_helper'

# Unit Test for RocketJob::Job
class DirmonEntryTest < Minitest::Test
  class WithFullFileNameJob < RocketJob::Job
    # Dirmon will store the filename in this property when starting the job
    field :upload_file_name, type: String

    def perform
      # Do something with the file name stored in :upload_file_name
    end
  end

  class SumJob < RocketJob::Job
    @result = nil

    # For temp test data
    class << self
      attr_reader :result
    end

    def perform(a, b)
      @result = a + b
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
          assert_nil entry.job_class
        end
      end

      describe 'with an unknown job_class_name' do
        it 'return nil' do
          entry = RocketJob::DirmonEntry.new(job_class_name: 'FakeJobThatDoesNotExistAnyWhereIPromise')
          assert_nil entry.job_class
        end
      end

      describe 'with a valid job_class_name' do
        it 'return job class' do
          entry = RocketJob::DirmonEntry.new(job_class_name: 'RocketJob::Job')
          assert_equal RocketJob::Job, entry.job_class
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
        @dirmon_entry = RocketJob::DirmonEntry.new(job_class_name: 'DirmonEntryTest::WithFullFileNameJob', pattern: 'test/files/**')
        @dirmon_entry.enable!
        assert @dirmon_entry.valid?, @dirmon_entry.errors.messages.ai
      end

      after do
        @dirmon_entry.destroy if @dirmon_entry&.new_record?
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
        assert entry = RocketJob::DirmonEntry.new(job_class_name: 'DirmonEntryTest::WithFullFileNameJob')
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
          properties:        {priority: 23},
          archive_directory: @archive_directory
        )
        @job          = DirmonEntryTest::WithFullFileNameJob.new(
          @entry.properties
        )
        @file         = Tempfile.new('archive')
        @file_name    = @file.path
        @pathname     = Pathname.new(@file_name)
        File.open(@file_name, 'w') { |file| file.write('Hello World') }
        assert File.exist?(@file_name)
        @archive_real_name = @archive_path.join("#{@job.id}_#{File.basename(@file_name)}").to_s
      end

      after do
        @file&.delete
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
          assert_equal archive_real_name, job.upload_file_name
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
          @entry = RocketJob::DirmonEntry.new(
            pattern:           'test/files/**/*',
            job_class_name:    'DirmonEntryTest::WithFullFileNameJob',
            archive_directory: @archive_directory
          )
          job    = @entry.later(@pathname)
          assert_equal Pathname.new(@archive_directory).join("#{job.id}_#{File.basename(@file_name)}").realdirpath.to_s, job.upload_file_name
          assert job.queued?
          assert_equal 50, job.priority
        end

        it 'fails with bad job class name' do
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
          assert_nil @entry.archive_directory
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
          assert_nil @entry.archive_directory
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
          assert_nil @entry.archive_directory
          assert_equal 0, files.count
        end

        describe '#strip_whitespace' do
          it 'removes white space' do
            @entry = RocketJob::DirmonEntry.new(
              pattern:           ' test/files/*',
              archive_directory: ' test/archive/ '
            )
            @entry.send(:strip_whitespace)
            assert_equal 'test/files/*', @entry.pattern
            assert_equal 'test/archive/', @entry.archive_directory
          end
        end
      end
    end
  end
end

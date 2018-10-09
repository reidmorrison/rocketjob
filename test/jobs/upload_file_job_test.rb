require_relative '../test_helper'

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
      field :upload_file_name, type: String
      field :original_file_name, type: String
      field :saved_streams, type: Array

      def upload(upload_file_name, streams: nil, file_name: nil)
        self.upload_file_name   = upload_file_name
        self.saved_streams      = streams
        self.saved_streams      ||= IOStreams.streams_for_file_name(file_name) if file_name
        self.original_file_name = file_name
      end

      def perform
      end
    end

    class BadJob < RocketJob::Job
      def perform
      end
    end

    describe RocketJob::Jobs::UploadFileJob do
      before do
        RocketJob::Job.delete_all
      end

      describe '#valid?' do
        it 'validates upload_file_name' do
          job = RocketJob::Jobs::UploadFileJob.new(job_class_name: UploadFileJobTest::TestJob.to_s)
          refute job.valid?
          assert_equal ["can't be blank"], job.errors.messages[:upload_file_name]
        end

        it 'validates file does not exist' do
          job = RocketJob::Jobs::UploadFileJob.new(
            job_class_name:   UploadFileJobTest::TestJob.to_s,
            upload_file_name: '/tmp/blah'
          )
          refute job.valid?
          assert_equal ['Upload file: /tmp/blah does not exist.'], job.errors.messages[:upload_file_name]
        end

        it 'validates job_class_name' do
          job = RocketJob::Jobs::UploadFileJob.new(job_class_name: UploadFileJobTest::BadJob.to_s)
          refute job.valid?
          assert_equal ['UploadFileJobTest::BadJob must implement any one of: :upload :upload_file_name= :full_file_name= instance methods'], job.errors.messages[:job_class_name]
        end

        it 'with valid job and upload_file_name' do
          job = RocketJob::Jobs::UploadFileJob.new(
            job_class_name:   UploadFileJobTest::TestJob.to_s,
            upload_file_name: __FILE__
          )
          assert job.valid?
        end
      end

      describe '#perform' do
        let :job do
          RocketJob::Jobs::UploadFileJob.new(
            job_class_name:   UploadFileJobTest::TestJob.name,
            upload_file_name: __FILE__
          )
        end

        it 'creates the job' do
          job.perform_now
          assert_equal 1, UploadFileJobTest::TestJob.count
          assert job = UploadFileJobTest::TestJob.first
        end

        it 'calls upload' do
          job.perform_now
          assert job = UploadFileJobTest::TestJob.first
          assert_equal __FILE__, job.upload_file_name
        end

        it 'calls upload with original_file_name' do
          job.job_class_name = BatchTestJob.name
          job.perform_now
          assert created_job = UploadFileJobTest::BatchTestJob.first
          assert_equal __FILE__, created_job.upload_file_name
          assert_nil created_job.saved_streams
        end

        it 'job retains the original_file_name when present' do
          job.job_class_name     = BatchTestJob.name
          job.original_file_name = 'file.zip'
          job.perform_now
          assert created_job = UploadFileJobTest::BatchTestJob.first
          assert_equal 'file.zip', created_job.original_file_name
          assert_equal __FILE__, created_job.upload_file_name
          assert_equal %i[zip], created_job.saved_streams
        end
      end
    end
  end
end

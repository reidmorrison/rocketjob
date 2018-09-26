require 'fileutils'
begin
  require 'iostreams'
rescue LoadError
  # Optional dependency
end

module RocketJob
  module Jobs
    # Job to upload a file into another job.
    #
    # Intended for use by DirmonJob to upload a file into a specified job.
    #
    # Can be used directly for any job class, as long as that job responds
    # to `#upload`.
    class UploadFileJob < RocketJob::Job
      self.priority = 30

      # Name of the job class to instantiate and upload the file into.
      field :job_class_name, type: String, user_editable: true

      # Properties to assign to the job when it is created.
      field :properties, type: Hash, default: {}, user_editable: true

      # File to upload
      field :upload_file_name, type: String, user_editable: true

      # The original Input file name.
      # Used by #upload to extract the IOStreams when present.
      field :original_file_name, type: String, user_editable: true

      # Optionally set the job id for the downstream job
      # Useful when for example the archived file should contain the job id for the downstream job.
      field :job_id, type: BSON::ObjectId

      validates_presence_of :upload_file_name, :job_class_name
      validate :job_is_a_rocket_job
      validate :job_implements_upload
      validate :file_exists

      # Create the job and upload the file into it.
      def perform
        job    = job_class.new(properties)
        job.id = job_id if job_id
        upload_file(job)
        job.save!
      rescue StandardError => exc
        # Prevent partial uploads
        job&.cleanup! if job.respond_to?(:cleanup!)
        raise(exc)
      end

      private

      def job_class
        @job_class ||= job_class_name.constantize
      rescue NameError
        nil
      end

      def upload_file(job)
        if job.respond_to?(:upload)
          if original_file_name
            job.upload(upload_file_name, file_name: original_file_name)
          else
            job.upload(upload_file_name)
          end
        elsif job.respond_to?(:upload_file_name=)
          job.upload_file_name = upload_file_name
        elsif job.respond_to?(:full_file_name=)
          job.full_file_name = upload_file_name
        else
          raise(ArgumentError, "Model #{job_class_name} must implement '#upload', or have attribute 'upload_file_name' or 'full_file_name'")
        end
      end

      # Validates job_class is a Rocket Job
      def job_is_a_rocket_job
        klass = job_class
        return if klass.nil? || klass.ancestors&.include?(RocketJob::Job)
        errors.add(:job_class_name, "Model #{job_class_name} must be defined and inherit from RocketJob::Job")
      end

      VALID_INSTANCE_METHODS = %i[upload upload_file_name= full_file_name=].freeze

      # Validates job_class is a Rocket Job
      def job_implements_upload
        klass = job_class
        return if klass.nil? || klass.instance_methods.any? { |m| VALID_INSTANCE_METHODS.include?(m) }
        errors.add(:job_class_name, "#{job_class} must implement any one of: :#{VALID_INSTANCE_METHODS.join(' :')} instance methods")
      end

      def file_exists
        return if upload_file_name.nil? || File.exist?(upload_file_name)
        errors.add(:upload_file_name, "Upload file: #{upload_file_name} does not exist.")
      end
    end
  end
end

require "fileutils"
require "uri"

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
      field :upload_file_name, type: IOStreams::Path, user_editable: true

      # The original Input file name, without any credentials, see IOStreams::Path#display_name.
      # Used by #upload to extract the IOStreams when present.
      field :original_file_name, type: String, user_editable: true

      # Optionally set the job id for the downstream job
      # Useful when for example the archived file should contain the job id for the downstream job.
      field :job_id, type: BSON::ObjectId

      validates_presence_of :upload_file_name, :job_class_name
      validate :job_class_can_be_started
      validate :file_exists
      validate :job_has_properties

      # The methods that #upload_file uploads the file with, whichever the job has: its #upload, or the file name that
      # it reads.
      VALID_INSTANCE_METHODS = %i[upload upload_file_name= full_file_name=].freeze
      private_constant :VALID_INSTANCE_METHODS

      # Returns [Array<String>] why an UploadFileJob cannot start a job of the named class: it is not defined, does not
      # inherit from RocketJob::Job, or has none of the methods that the file is uploaded with. Empty when it can.
      # A Dirmon entry asks it, so that the files it finds are not archived for a job that cannot be started.
      def self.job_class_errors(job_class_name)
        klass = job_class_name.to_s.safe_constantize
        unless klass.is_a?(Class) && klass <= RocketJob::Job
          return ["Job #{job_class_name} must be defined and inherit from RocketJob::Job"]
        end
        return [] if klass.instance_methods.intersect?(VALID_INSTANCE_METHODS)

        ["#{klass} must implement any one of: :#{VALID_INSTANCE_METHODS.join(' :')} instance methods"]
      end

      # Create the job and upload the file into it.
      def perform
        job    = job_class.from_properties(properties)
        job.id = job_id if job_id
        upload_file(job)
        job.save!
      rescue Exception => e
        # Prevent partial uploads
        job&.cleanup! if job.respond_to?(:cleanup!)
        raise(e)
      end

      # Returns [Hash] the attributes to show, see RocketJob::Plugins::Job::Model#display_attributes, with the paths
      # in the properties shown without any credentials. The job class decides which of its properties are paths.
      def display_attributes
        attrs = super
        klass = job_class
        attrs["properties"] = klass.display_properties(attrs["properties"]) if klass && attrs["properties"].is_a?(Hash)
        attrs
      end

      private

      def job_class
        @job_class ||= job_class_name.constantize
      rescue NameError
        nil
      end

      def upload_file(job)
        if job.respond_to?(:upload)
          # Return the database connection for this thread back to the connection pool
          # in case the upload takes a long time and the database connection expires.
          RocketJob.release_active_record_connections

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
          raise(
            ArgumentError,
            "Model #{job_class_name} must implement '#upload', or have attribute 'upload_file_name' or 'full_file_name'"
          )
        end
      end

      # Validates that an UploadFileJob can start a job of the class, see .job_class_errors. A class that is not
      # defined is accepted, since the server that creates this job, such as Dirmon's, may not load every job class:
      # this job then fails when it runs, and can be retried once the class is deployed, while the file that it
      # uploads is kept in the archive.
      def job_class_can_be_started
        return unless job_class

        self.class.job_class_errors(job_class_name).each { |message| errors.add(:job_class_name, message) }
      end

      def file_exists
        # Only check for file existence when it is a local file
        return unless upload_file_name.is_a?(IOStreams::Paths::File)
        return errors.add(:upload_file_name, "Upload file name can't be blank.") if upload_file_name.to_s == ""

        return if upload_file_name.exist?

        errors.add(:upload_file_name, "Upload file: #{RocketJob.path_display_name(upload_file_name)} does not exist.")
      rescue NotImplementedError
        nil
      end

      # Can the properties build the job? The job class decides, see RocketJob::Plugins::Job::Model.property_errors.
      def job_has_properties
        klass = job_class
        return unless klass.respond_to?(:property_errors)

        klass.property_errors(properties).each { |message| errors.add(:properties, message) }
      end
    end
  end
end

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

      # The original Input file name, without any credentials, see RocketJob::DirmonEntry#file_display_name.
      # Used by #upload to extract the IOStreams when present.
      # Shown without any credentials too, see #display_attributes, since a job saved by Rocket Job 7.1, or created or
      # edited by hand, can hold the url of a file with its user name and password.
      field :original_file_name, type: String, user_editable: true, path: true

      # Optionally set the job id for the downstream job
      # Useful when for example the archived file should contain the job id for the downstream job.
      field :job_id, type: BSON::ObjectId

      validates_presence_of :upload_file_name, :job_class_name
      # Checked when they are set or changed, not each time the job is saved, so that a saved job can still be
      # aborted, retried or paused, such as in a web interface, see #job_settings_changed? and #upload_file_name_set?.
      validate :job_class_can_be_started, :job_has_properties, if: :job_settings_changed?
      validate :file_exists, if: :upload_file_name_set?
      after_initialize :convert_saved_properties, unless: :new_record?

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

      # Returns [Array<String>] why an UploadFileJob with the job class name and properties would not be valid: the
      # messages of its own validations of them, such as .job_class_errors, or why the job class cannot be built from
      # the properties, see RocketJob::Plugins::Job::Model.property_errors. Empty when it would be valid, which it is
      # for a job class that this process does not load, see #job_class_can_be_started.
      # A Dirmon entry asks it before it archives a file, so that the file is not archived for an UploadFileJob that
      # cannot be created, such as for properties that were saved before the job class changed.
      def self.job_errors(job_class_name, properties)
        job = new(job_class_name: job_class_name, properties: properties)
        job.validate
        job.errors.messages_for(:job_class_name) + job.errors.messages_for(:properties)
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
      # in the properties shown without any credentials. The job class decides which of its properties are paths. They
      # are shown as stored when the job class is not defined, or is not a Rocket Job.
      def display_attributes
        attrs = super
        klass = job_class
        if klass.is_a?(Class) && klass <= RocketJob::Job && attrs["properties"].is_a?(Hash)
          attrs["properties"] = klass.display_properties(attrs["properties"])
        end
        attrs
      end

      private

      # Not memoized, so that it follows a change of the job class name, such as one made in a web interface to fix a
      # failed job.
      def job_class
        job_class_name.to_s.safe_constantize
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

      # Validates that the file to upload exists, whichever storage it is on, such as S3 or SFTP, see
      # #upload_file_name_set?. Only an answer from the storage that the file is not there fails it: it is not checked
      # when this process cannot ask, such as a web server that cannot reach the storage, resolve its host, or read it,
      # or that lacks the gem that reads it, nor when the storage cannot answer whether a file exists, so that the job
      # can still be saved there. It then fails when it runs, if the file is not there.
      def file_exists
        return upload_file_name_url_valid if upload_file_name.is_a?(String)
        return if upload_file_name.nil?
        return errors.add(:upload_file_name, "Upload file name can't be blank.") if upload_file_name.to_s == ""
        return unless file_missing?

        errors.add(:upload_file_name, "Upload file: #{RocketJob.path_display_name(upload_file_name)} does not exist.")
      end

      # Returns [true|false] whether the storage answers that the file to upload is not there, false when it could not
      # be asked, see #file_exists, whatever its store raised, such as an error of the AWS SDK for an S3 endpoint whose
      # host does not resolve, which IOStreams does not tag, apart from IOStreams::Errors::AccessDenied, for a path that
      # the application does not allow, see IOStreams.allowed_paths.
      def file_missing?
        !upload_file_name.exist?
      rescue IOStreams::Errors::AccessDenied
        raise
      rescue StandardError, NotImplementedError, LoadError => e
        logger.info("Not checking that #{RocketJob.path_display_name(upload_file_name)} exists, since its storage " \
                    "could not be asked: #{e.class}")
        false
      end

      # A url that IOStreams cannot make a path of is read as stored, a String, see IOStreams::Path.demongoize, so one
      # that is set or changed is checked here, rather than when the job runs, see IOStreams::Path.invalid_url?. A saved
      # one is not, see #upload_file_name_set?, so that a job whose url has a scheme that only the servers that run it
      # register can still be saved elsewhere, such as when it is aborted in a web interface.
      def upload_file_name_url_valid
        return unless IOStreams::Path.invalid_url?(upload_file_name)

        # The url is not included in the message, since one that cannot be parsed can hold credentials.
        errors.add(:upload_file_name, "Upload file name is not a path or url that IOStreams can read.")
      end

      # Converts the properties that were saved before Rocket Job v8, such as an input category's `mode`, which v8
      # replaced, as the job class reads them, see RocketJob::Plugins::Job::Model.convert_saved_properties. Setting them
      # changes this job, so that saving it saves them. Kept as they are when the job class is not loaded.
      def convert_saved_properties
        klass = job_class
        return unless klass.respond_to?(:convert_saved_properties) && properties.is_a?(Hash)

        converted = klass.convert_saved_properties(properties)
        return if converted == properties

        self.properties = converted
        @converted_saved_properties = converted.deep_dup
      end

      # Can the properties build the job? The job class decides, see RocketJob::Plugins::Job::Model.property_errors.
      def job_has_properties
        klass = job_class
        return unless klass.respond_to?(:property_errors)

        klass.property_errors(properties).each { |message| errors.add(:properties, message) }
      end

      # Whether the job class name or properties are new or changed, so are checked. A saved job is not checked
      # again, so that its state can still be changed after its job class changed and no longer accepts its
      # properties. It then fails when it runs and builds the job, see #perform, until they are corrected. Properties
      # that only #convert_saved_properties changed are not checked either, since they were saved as they were.
      def job_settings_changed?
        return true if new_record? || job_class_name_changed?

        properties_changed? && properties != @converted_saved_properties
      end

      # Whether the file to upload is new or changed, so is checked. A saved one is not, since the file is moved or
      # deleted once it is uploaded, and can be on a disk that only the servers that run the job can read.
      def upload_file_name_set?
        new_record? || upload_file_name_changed?
      end
    end
  end
end

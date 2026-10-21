require "concurrent"
require "fileutils"
module RocketJob
  class DirmonEntry
    include Plugins::Document
    include Plugins::StateMachine

    # The default archive directory that is used when the job being queued does not respond
    # to #upload, and does not have an `archive_directory` specified in this entry
    class_attribute :default_archive_directory
    self.default_archive_directory = "archive".freeze

    store_in collection: "rocket_job.dirmon_entries"

    # User defined name used to identify this DirmonEntry in the Web Interface.
    field :name, type: String

    # Pattern for finding files
    #
    # Example: All files ending in '.csv' in the input_files/process1 directory
    #   input_files/process1/*.csv
    #
    # Example: All files in the input_files/process1 directory and all sub-directories
    #   input_files/process2/**/*
    #
    # Example: All files in the input_files/process2 directory with .csv or .txt extensions
    #   input_files/process2/*.{csv,txt}
    #
    # For details on valid pattern values, see: http://ruby-doc.org/core-2.2.2/Dir.html#method-c-glob
    #
    # Note
    # - If there is no '*' in the pattern then an exact filename match is expected
    # - The pattern is not validated to ensure the path exists, it will be validated against the
    #   `whitelist_paths` when processed by DirmonJob
    field :pattern, type: String

    # Job to enqueue for processing for every file that matches the pattern
    #
    # Example:
    #   "ProcessItJob"
    field :job_class_name, type: String

    # Any job properties to set
    #
    # Example, override the default job priority:
    #   { priority: 45 }
    field :properties, type: Hash, default: {}

    # Archive directory to move files to when processed to prevent processing the
    # file again.
    #
    # If supplied, the file will be moved to this directory before the job is started
    # If the file was in a sub-directory, the corresponding sub-directory will
    # be created in the archive directory.
    field :archive_directory, type: String, default: default_archive_directory

    # If this DirmonEntry is in the failed state, exception contains the cause
    embeds_one :exception, class_name: "RocketJob::JobException"

    #
    # Read-only attributes
    #

    # Current state, as set by the state machine. Do not modify directly.
    field :state, type: Mongoid::StringifiedSymbol, default: :pending

    # Unique index on pattern to help prevent two entries from scanning the same files
    index({pattern: 1}, background: true, unique: true)

    before_validation :strip_whitespace
    validates_presence_of :pattern, :job_class_name, :archive_directory
    validate :job_is_a_rocket_job
    validate :job_has_properties
    validates_uniqueness_of :pattern, :name

    # State Machine events and transitions
    #
    # :pending -> :enabled  -> :disabled
    #                       -> :failed
    #          -> :failed   -> :active
    #                       -> :disabled
    #          -> :disabled -> :active
    aasm column: :state, whiny_persistence: true do
      # DirmonEntry is `pending` until it is approved
      state :pending, initial: true

      # DirmonEntry is Enabled and will be included by DirmonJob
      state :enabled

      # DirmonEntry failed during processing and requires manual intervention
      # See the exception for the reason for failing this entry
      # For example: access denied, whitelist_path security violation, etc.
      state :failed

      # DirmonEntry has been manually disabled
      state :disabled

      event :enable do
        transitions from: :pending, to: :enabled
        transitions from: :disabled, to: :enabled
        transitions from: :failed, to: :enabled
      end

      event :disable do
        transitions from: :enabled, to: :disabled
        transitions from: :failed, to: :disabled
      end

      event :fail, before: :set_exception do
        transitions from: :enabled, to: :failed
      end
    end

    # Security Settings
    #
    # A whitelist of paths from which to process files.
    # This prevents accidental or malicious `pattern`s from processing files from anywhere
    # in the system that the user under which Dirmon is running can access.
    #
    # All resolved `pattern`s must start with one of the whitelisted path, otherwise they will be rejected
    #
    # Note:
    # - If no whitelist paths have been added, then a whitelist check is _not_ performed
    # - Relative paths can be used, but are not considered safe since they can be manipulated
    # - These paths should be assigned in an initializer and not editable via the Web UI to ensure
    #   that they are not tampered with
    #
    # Default: [] ==> Do not enforce whitelists
    #
    # Returns [Array<String>] a copy of the whitelisted paths
    def self.get_whitelist_paths
      whitelist_paths.dup
    end

    # Add a path to the whitelist
    # Raises: Errno::ENOENT: No such file or directory
    def self.add_whitelist_path(path)
      # Confirms that path exists
      path = IOStreams.path(path).realpath.to_s
      whitelist_paths << path
      whitelist_paths.uniq!
      path
    end

    # Deletes a path from the whitelist paths
    # Raises: Errno::ENOENT: No such file or directory
    def self.delete_whitelist_path(path)
      # Confirms that path exists
      path = IOStreams.path(path).realpath.to_s
      whitelist_paths.delete(path)
      whitelist_paths.uniq!
      path
    end

    # Returns [Hash<String:Integer>] of the number of dirmon entries in each state.
    # Note: If there are no workers in that particular state then the hash will not have a value for it.
    #
    # Example dirmon entries in every state:
    #   RocketJob::DirmonEntry.counts_by_state
    #   # => {
    #          :pending => 1,
    #          :enabled => 37,
    #          :failed => 1,
    #          :disabled => 3
    #        }
    #
    # Example no dirmon entries:
    #   RocketJob::Job.counts_by_state
    #   # => {}
    def self.counts_by_state
      counts = {}
      collection.aggregate([{"$group" => {_id: "$state", count: {"$sum" => 1}}}]).each do |result|
        counts[result["_id"].to_sym] = result["count"]
      end
      counts
    end

    # Yields [IOStreams::Path] for each file found that matches the current pattern.
    def each
      SemanticLogger.named_tagged(dirmon_entry: id.to_s) do
        # Case insensitive filename matching
        IOStreams.each_child(pattern) do |path|
          path = path.realpath
          # Skip archive directories
          next if path.to_s.include?(archive_directory || self.class.default_archive_directory)

          # Security check?
          if whitelist_paths.size.positive? && whitelist_paths.none? { |whitepath| path.to_s.start_with?(whitepath) }
            logger.warn "Skipping file: #{path.display_name} since it is not in any of the whitelisted paths: #{whitelist_paths.join(', ')}"
            next
          end

          # File must be writable so it can be removed after processing
          if path.respond_to?(:writable?) && !path.writable?
            logger.warn "Skipping file: #{file_name} since it is not writable by the current user. Must be able to delete/move the file after queueing the job"
            next
          end
          yield(path)
        end
      end
    end

    # Set exception information for this DirmonEntry and fail it
    def set_exception(worker_name, exc_or_message)
      if exc_or_message.is_a?(Exception)
        self.exception        = JobException.from_exception(exc_or_message)
        exception.worker_name = worker_name
      else
        build_exception(
          class_name:  "RocketJob::DirmonEntryException",
          message:     exc_or_message,
          backtrace:   [],
          worker_name: worker_name
        )
      end
    end

    # Returns [Array<RocketJob::SchemaProposal>] the schemas proposed to replace the deprecated category options in the
    # properties of this entry, which its job class proposes, see
    # RocketJob::Batch::Categories::ClassMethods#property_schema_proposals. None when its job class is not loaded.
    def schema_proposals
      klass = job_class
      return [] unless klass && properties.is_a?(Hash)

      klass.property_schema_proposals(properties, "Dirmon entry #{name.inspect} #{id}")
    end

    # Returns [String] the pattern to show, for example in a web interface, which leaves out any credentials,
    # such as the user name and password of `sftp://user:password@host/in/*.csv`, see IOStreams::Path#display_name.
    #
    # A url cannot hold some pattern characters, such as the braces of `sftp://host/in/*.{csv,txt}`. Such a pattern
    # is shown as the display name of the directory that is scanned, followed by the pattern within it,
    # the same way that IOStreams.each_child splits it.
    #
    # Unless the pattern within the directory has a `?`, which cannot be told apart from the query of a url, such as
    # `sftp://host/in/*.{csv,txt}?password=secret`, where the query holds ssh options, which could hold a secret.
    def pattern_display_name
      display_name = RocketJob.path_display_name(pattern)
      return display_name unless display_name == RocketJob::INVALID_PATH_DISPLAY_NAME

      matcher = IOStreams::Paths::Matcher.new(nil, pattern)
      return display_name if matcher.pattern.nil? || matcher.pattern == pattern || matcher.pattern.include?("?")

      "#{matcher.path.display_name}/#{matcher.pattern}"
    rescue StandardError, LoadError
      # The directory is not a valid path, or needs a gem that is not installed in this process.
      RocketJob::INVALID_PATH_DISPLAY_NAME
    end

    # Returns [String] the archive directory to show, without any credentials, see #pattern_display_name.
    def archive_directory_display_name
      RocketJob.path_display_name(archive_directory)
    end

    # Returns [Hash] the properties to show, with each path or url that the job class holds in them shown without
    # any credentials, see RocketJob::Plugins::Job::Model.display_properties. The properties are shown as stored when
    # the job class is not defined, since then it cannot say which of them are paths.
    def display_properties
      klass = job_class
      klass ? klass.display_properties(properties) : properties
    end

    # Returns [RocketJob::DirmonEntry] a new, unsaved, pending entry with the settings of this entry, such as its
    # job class and properties, overridden by the supplied attributes, which usually include a new name and pattern.
    #
    # Only the settings in REPLICATED_ATTRIBUTES are copied, not what happened to this entry, such as its state,
    # or why it failed.
    #
    # The name and pattern must each be unique, so the replica is not valid until both are changed. They are copied
    # so that, for example, a web interface can show them to be edited.
    def replicate(**attributes)
      entry = self.class.new(self.attributes.slice(*REPLICATED_ATTRIBUTES).deep_dup)
      entry.assign_attributes(attributes)
      entry
    end

    # Returns the Job to be created.
    def job_class
      return if job_class_name.nil?

      job_class_name.constantize
    rescue NameError
      nil
    end

    # Archives the file, then kicks off a file upload job to upload the archived file.
    def later(iopath)
      job_id       = BSON::ObjectId.new
      archive_path = archive_iopath(iopath).join("#{job_id}_#{iopath.basename}")
      iopath.move_to(archive_path)

      job = RocketJob::Jobs::UploadFileJob.create!(
        job_class_name:     job_class_name,
        properties:         properties,
        description:        "#{name}: #{iopath.basename}",
        upload_file_name:   archive_path,
        original_file_name: iopath.display_name,
        job_id:             job_id
      )

      logger.info(
        message: "Created RocketJob::Jobs::UploadFileJob",
        payload: {
          dirmon_entry_name:  name,
          upload_file_name:   archive_path.display_name,
          original_file_name: iopath.display_name,
          job_class_name:     job_class_name,
          job_id:             job_id.to_s,
          upload_job_id:      job.id.to_s
        }
      )
      job
    end

    private

    # The settings of an entry, which #replicate copies. A new field is not copied unless it is added here.
    REPLICATED_ATTRIBUTES = %w[name pattern job_class_name properties archive_directory].freeze
    private_constant :REPLICATED_ATTRIBUTES

    # strip whitespaces from all variables that reference paths or patterns
    def strip_whitespace
      self.pattern           = pattern.strip unless pattern.nil?
      self.archive_directory = archive_directory.strip unless archive_directory.nil?
    end

    class_attribute :whitelist_paths
    self.whitelist_paths = Concurrent::Array.new

    # Returns [Pathname] to the archive directory, and creates it if it does not exist.
    #
    # If `archive_directory` is a relative path, it is appended to the `file_pathname`.
    # If `archive_directory` is an absolute path, it is returned as-is.
    def archive_iopath(iopath)
      path = IOStreams.path(archive_directory)
      path.relative? ? iopath.directory.join(archive_directory) : path
    end

    # Validates job_class is a Rocket Job
    def job_is_a_rocket_job
      klass = job_class
      return if job_class_name.nil? || klass&.ancestors&.include?(RocketJob::Job)

      errors.add(:job_class_name, "Job #{job_class_name} must be defined and inherit from RocketJob::Job")
    end

    # Does the job have all the supplied properties
    def job_has_properties
      klass = job_class
      return unless klass

      # Mongoid 9 returns Hash field keys as Strings, earlier versions as Symbols.
      properties.each_pair do |raw_key, value|
        k = raw_key.to_sym
        next if klass.public_method_defined?(:"#{k}=")

        if %i[output_categories input_categories].include?(k)
          category_class = k == :input_categories ? RocketJob::Category::Input : RocketJob::Category::Output
          value.each do |category|
            category.each_pair do |key, _value|
              next if category_class.public_method_defined?(:"#{key}=")

              errors.add(
                :properties,
                "Unknown Property in #{k}: Attempted to set a value for #{key}.#{k} which is not allowed on the job #{job_class_name}"
              )
            end
          end
          next
        end

        errors.add(
          :properties,
          "Unknown Property: Attempted to set a value for #{k.inspect} which is not allowed on the job #{job_class_name}"
        )
      end
    end
  end
end

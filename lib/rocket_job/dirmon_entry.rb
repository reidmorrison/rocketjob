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

    # Number of seconds that the storage of an entry, such as an SFTP server, can be unavailable before the
    # entry fails. Until then the entry is scanned again on each run, see #storage_unavailable!.
    # Set to 0 to fail an entry the first time that its storage is unavailable.
    class_attribute :max_unavailable_seconds
    self.max_unavailable_seconds = 3600

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

    # When the storage of this entry could not be reached, the time that it was first unavailable,
    # see #storage_unavailable!. Cleared once a scan succeeds, or the entry is enabled again.
    field :unavailable_at, type: Time

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

      event :enable, before: :clear_unavailable_at do
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
    # Raises: IOStreams::Errors::NotFound when the path does not exist
    def self.add_whitelist_path(path)
      # Confirms that path exists
      path = IOStreams.path(path).realpath.to_s
      whitelist_paths << path
      whitelist_paths.uniq!
      path
    end

    # Deletes a path from the whitelist paths
    # Raises: IOStreams::Errors::NotFound when the path does not exist
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
          path = existing_realpath(path)
          next unless path

          # Skip archive directories
          next if path.to_s.include?(archive_directory || self.class.default_archive_directory)

          # Security check?
          if whitelist_paths.size.positive? && whitelist_paths.none? { |whitepath| path.to_s.start_with?(whitepath) }
            logger.warn "Skipping file: #{RocketJob.path_display_name(path)} since it is not in any of the whitelisted paths: #{whitelist_paths.join(', ')}"
            next
          end

          # The file is moved to the archive directory when its job is queued, which requires
          # write access to the directory that contains it.
          if path.is_a?(IOStreams::Paths::File) && !::File.writable?(path.directory.to_s)
            logger.warn "Skipping file: #{RocketJob.path_display_name(path)} since its directory is not writable by the current user. Must be able to delete/move the file after queueing the job"
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

    # Records that the storage of this entry could not be reached, such as an SFTP server that is restarting,
    # see IOStreams::Errors::Unavailable, so that the entry is scanned again on the next run.
    #
    # Fails this entry once its storage has been unavailable for longer than `max_unavailable_seconds`, since the
    # failure may not be temporary, for example when a server stays down.
    def storage_unavailable!(worker_name, exception)
      self.unavailable_at ||= Time.now
      unavailable_seconds = Time.now - unavailable_at
      if unavailable_seconds < max_unavailable_seconds
        logger.warn("Dirmon Entry: #{id} storage is unavailable. Scanning it again on the next run.", exception)
      else
        logger.error(
          "Dirmon Entry: #{id} storage has been unavailable for #{unavailable_seconds.round} seconds. " \
          "Moved to `failed` state to prevent processing again without manual intervention.",
          exception
        )
        fail(worker_name, exception)
      end
      save(validate: false)
    end

    # Records that the storage of this entry was available for a scan, which ends any outage,
    # see #storage_unavailable!.
    def storage_available!
      return if unavailable_at.nil?

      self.unavailable_at = nil
      save(validate: false)
    end

    # Returns [String] the pattern to show, for example in a web interface, which leaves out any credentials,
    # such as the user name and password of `sftp://user:password@host/in/*.csv`, see IOStreams::Path#display_name.
    #
    # A url cannot hold some pattern characters, such as the braces of `sftp://host/in/*.{csv,txt}`. Such a pattern
    # is shown as the display name of the directory that is scanned, followed by the pattern within it,
    # the same way that IOStreams.each_child splits it.
    def pattern_display_name
      display_name = RocketJob.path_display_name(pattern)
      return display_name unless display_name == RocketJob::INVALID_PATH_DISPLAY_NAME

      matcher = IOStreams::Paths::Matcher.new(pattern)
      return display_name if matcher.directory.empty?

      directory = RocketJob.path_display_name(matcher.directory)
      directory == RocketJob::INVALID_PATH_DISPLAY_NAME ? directory : "#{directory}/#{matcher.pattern}"
    rescue ArgumentError
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
    # why it failed, or when its storage became unavailable.
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
    #
    # A file whose name is not valid UTF-8, such as a Latin-1 name, is archived under a name that is, see
    # #archive_file_name, since the job holds the name of the archived file. The job's original file name shows
    # each byte that is not valid UTF-8 as `\xHH`, see #file_display_name.
    #
    # Returns [RocketJob::Jobs::UploadFileJob] the job, or nil when the file was removed after it was found.
    def later(iopath)
      job_id       = BSON::ObjectId.new
      archive_path = archive_iopath(iopath).join("#{job_id}_#{archive_file_name(iopath)}")
      return unless archive_file(iopath, archive_path)

      original_file_name = file_display_name(iopath)
      job                = RocketJob::Jobs::UploadFileJob.create!(
        job_class_name:     job_class_name,
        properties:         properties,
        description:        "#{name}: #{RocketJob.valid_utf8(iopath.basename)}",
        upload_file_name:   archive_path,
        original_file_name: original_file_name,
        job_id:             job_id
      )

      logger.info(
        message: "Created RocketJob::Jobs::UploadFileJob",
        payload: {
          dirmon_entry_name:  name,
          upload_file_name:   RocketJob.path_display_name(archive_path),
          original_file_name: original_file_name,
          job_class_name:     job_class_name,
          job_id:             job_id.to_s,
          upload_job_id:      job.id.to_s
        }
      )
      job
    end

    # Returns [String] the name of a file that this entry found, to save and log: its display name, see
    # RocketJob.path_display_name, or, when the path cannot build one, its path without its host or any
    # credentials, so that each file still has a name of its own, which ends with its extensions, such as `.csv.gz`.
    def file_display_name(iopath)
      name = RocketJob.path_display_name(iopath)
      name == RocketJob::INVALID_PATH_DISPLAY_NAME ? RocketJob.valid_utf8(iopath.path) : name
    end

    private

    # The settings of an entry, which #replicate copies. A new field is not copied unless it is added here.
    REPLICATED_ATTRIBUTES = %w[name pattern job_class_name properties archive_directory].freeze
    private_constant :REPLICATED_ATTRIBUTES

    # The properties that hold the settings of the job's categories.
    CATEGORY_PROPERTIES = %i[input_categories output_categories].freeze
    private_constant :CATEGORY_PROPERTIES

    # An entry that is enabled again starts a new period in which its storage can be unavailable.
    def clear_unavailable_at
      self.unavailable_at = nil
    end

    # strip whitespaces from all variables that reference paths or patterns
    def strip_whitespace
      self.pattern           = pattern.strip unless pattern.nil?
      self.archive_directory = archive_directory.strip unless archive_directory.nil?
    end

    class_attribute :whitelist_paths
    self.whitelist_paths = Concurrent::Array.new

    # Returns [IOStreams::Path] the real path of the supplied file, or nil when it was removed after it was found,
    # whichever storage it is on.
    def existing_realpath(path)
      path.realpath
    rescue IOStreams::Errors::NotFound
      logger.info("Skipping file: #{RocketJob.path_display_name(path)} since it no longer exists")
      nil
    end

    # Returns [String] the name to archive the file under: its own name, with each byte that is not valid UTF-8, such
    # as the `é` of a Latin-1 name, replaced with U+FFFD, since MongoDB only stores UTF-8, and the job holds the name
    # of the archived file, see RocketJob.valid_utf8. Not shown as `\xHH`, since a `\` separates the directories of a
    # path on Windows. The job id that prefixes it keeps it unique.
    def archive_file_name(iopath)
      RocketJob.valid_utf8(iopath.basename, replacement: "\uFFFD")
    end

    # Moves the file to the archive path.
    #
    # Returns [true|false] whether the file was moved, false when it was removed after it was found.
    #
    # Raises IOStreams::Errors::NotFound when the file still exists, since then it is the archive path that was
    # not found, for example when its S3 bucket does not exist.
    def archive_file(iopath, archive_path)
      iopath.move_to(archive_path)
      true
    rescue IOStreams::Errors::NotFound
      raise if iopath.exist?

      logger.info("Skipping file: #{RocketJob.path_display_name(iopath)} since it no longer exists")
      false
    end

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

        # Checked before the job's setters, since a batch job has a setter for its categories, which would let a
        # category property that does not exist through.
        if CATEGORY_PROPERTIES.include?(k)
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

        next if klass.public_method_defined?(:"#{k}=")

        errors.add(
          :properties,
          "Unknown Property: Attempted to set a value for #{k.inspect} which is not allowed on the job #{job_class_name}"
        )
      end

      job_categories_are_valid if errors[:properties].empty?
    end

    # Are the category properties valid, such as the encoding of a category's files? Otherwise every file that this
    # entry finds would fail when its job is created, rather than when the entry is saved.
    #
    # The job is built from the properties, as for each file that is found, and each of its categories validates
    # itself.
    def job_categories_are_valid
      return unless job_class.respond_to?(:defined_input_categories)
      return unless properties.keys.any? { |key| CATEGORY_PROPERTIES.include?(key.to_sym) }

      job = job_class.from_properties(properties.deep_stringify_keys)
      {"Input" => job.input_categories, "Output" => job.output_categories}.each_pair do |direction, categories|
        categories.reject(&:valid?).each do |category|
          category.errors.full_messages.each do |message|
            errors.add(:properties, "#{direction} category #{category.name}: #{message}")
          end
        end
      end
    rescue ArgumentError => e
      # For example, a category that the job does not define.
      errors.add(:properties, e.message)
    end
  end
end

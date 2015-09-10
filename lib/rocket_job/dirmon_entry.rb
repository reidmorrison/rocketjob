require 'thread_safe'
require 'pathname'
require 'fileutils'
require 'aasm'
module RocketJob
  class DirmonEntry
    include MongoMapper::Document
    include AASM

    # @formatter:off
    # User defined name used to identify this DirmonEntry in Mission Control
    key :name,               String

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
    key :pattern,            String

    # Job to enqueue for processing for every file that matches the pattern
    #
    # Example:
    #   "ProcessItJob"
    key :job_class_name,     String

    # Any user supplied arguments for the method invocation
    # All keys must be UTF-8 strings. The values can be any valid BSON type:
    #   Integer
    #   Float
    #   Time    (UTC)
    #   String  (UTF-8)
    #   Array
    #   Hash
    #   True
    #   False
    #   Symbol
    #   nil
    #   Regular Expression
    #
    # Note: Date is not supported, convert it to a UTC time
    key :arguments,          Array

    # Any job properties to set
    #
    # Example, override the default job priority:
    #   { priority: 45 }
    key :properties,         Hash

    # Archive directory to move files to when processed to prevent processing the
    # file again.
    #
    # If supplied, the file will be moved to this directory before the job is started
    # If the file was in a sub-directory, the corresponding sub-directory will
    # be created in the archive directory.
    key :archive_directory,  String

    # Method to perform on the job, usually :perform
    key :perform_method,     Symbol, default: :perform

    # If this DirmonEntry is in the failed state, exception contains the cause
    one :exception,          class_name: 'RocketJob::JobException'

    # The maximum number of files that should ever match during a single poll of the pattern.
    #
    # Too many files could be as a result of an invalid pattern specification.
    # Exceeding this number will result in an exception being logged in a failed Dirmon instance.
    # Dirmon processing will continue with new instances.
    # TODO: Implement max_hits
    #key :max_hits,           Integer, default: 100

    #
    # Read-only attributes
    #

    # Current state, as set by AASM
    key :state,              Symbol, default: :pending

    # State Machine events and transitions
    #
    # :pending -> :enabled  -> :disabled
    #                       -> :failed
    #          -> :failed   -> :active
    #                       -> :disabled
    #          -> :disabled -> :active
    aasm column: :state do
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
        transitions from: :pending,  to: :enabled
        transitions from: :disabled, to: :enabled
      end

      event :disable do
        transitions from: :enabled, to: :disabled
        transitions from: :failed,  to: :disabled
      end

      event :fail do
        transitions from: :enabled, to: :failed
      end
    end

    # @formatter:on
    validates_presence_of :pattern, :job_class_name, :perform_method

    validates_each :perform_method do |record, attr, value|
      if (klass = record.job_class) && !klass.instance_methods.include?(value)
        record.errors.add(attr, "Method not implemented by #{record.job_class_name}")
      end
    end

    validates_each :job_class_name do |record, attr, value|
      exists =
        begin
          value.nil? ? false : record.job_class.ancestors.include?(RocketJob::Job)
        rescue NameError
          false
        end
      record.errors.add(attr, 'job_class_name must be defined and must be derived from RocketJob::Job') unless exists
    end

    validates_each :arguments do |record, attr, value|
      if (klass = record.job_class) && klass.instance_methods.include?(record.perform_method)
        count = klass.argument_count(record.perform_method)
        record.errors.add(attr, "There must be #{count} argument(s)") if value.size != count
      end
    end

    validates_each :properties do |record, attr, value|
      if record.job_class && (methods = record.job_class.instance_methods)
        value.each_pair do |k, v|
          record.errors.add(attr, "Unknown property: #{k.inspect} with value: #{v}") unless methods.include?("#{k}=".to_sym)
        end
      end
    end

    # Create indexes
    def self.create_indexes
      # Unique index on pattern to help prevent two entries from scanning the same files
      ensure_index({pattern: 1}, background: true, unique: true)
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
    def self.whitelist_paths
      @@whitelist_paths.dup
    end

    # Add a path to the whitelist
    # Raises: Errno::ENOENT: No such file or directory
    def self.add_whitelist_path(path)
      # Confirms that path exists
      path = Pathname.new(path).realpath.to_s
      @@whitelist_paths << path
      @@whitelist_paths.uniq!
      path
    end

    # Deletes a path from the whitelist paths
    # Raises: Errno::ENOENT: No such file or directory
    def self.delete_whitelist_path(path)
      # Confirms that path exists
      path = Pathname.new(path).realpath.to_s
      @@whitelist_paths.delete(path)
      @@whitelist_paths.uniq!
      path
    end

    # The default archive directory that is used when the job being queued does not respond
    # to #file_store_upload or #upload, and do not have an `archive_directory` specified in this entry
    cattr_accessor :default_archive_directory

    @@default_archive_directory = '_archive'.freeze

    # Returns [Pathname] the archive_directory if set, otherwise the default_archive_directory
    # Creates the archive directory if one is set
    def archive_pathname
      @archive_pathname ||= begin
        if archive_directory
          path = Pathname.new(archive_directory)
          path.mkpath unless path.exist?
          path.realpath
        else
          Pathname.new(self.class.default_archive_directory).realdirpath
        end
      end
    end

    # Passes each filename [Pathname] found that matches the pattern into the supplied block
    def each(&block)
      logger.tagged("DirmonEntry:#{id}") do
        Pathname.glob(pattern).each do |pathname|
          next if pathname.directory?
          pathname  = pathname.realpath
          file_name = pathname.to_s

          # Skip archive directories
          next if file_name.start_with?(archive_pathname.to_s)

          # Security check?
          if (@@whitelist_paths.size > 0) && @@whitelist_paths.none? { |whitepath| file_name.start_with?(whitepath) }
            logger.warn "Ignoring file: #{file_name} since it is not in any of the whitelisted paths: #{whitelist_paths.join(', ')}"
            next
          end

          # File must be writable so it can be removed after processing
          unless pathname.writable?
            logger.warn "Ignoring file: #{file_name} since it is not writable by the current user. Must be able to delete/move the file after queueing the job"
            next
          end
          block.call(pathname)
        end
      end
    end

    # Set exception information for this DirmonEntry and fail it
    def fail_with_exception!(worker_name, exc_or_message)
      if exc_or_message.is_a?(Exception)
        self.exception        = JobException.from_exception(exc_or_message)
        exception.worker_name = worker_name
      else
        build_exception(
          class_name:  'RocketJob::DirmonEntryException',
          message:     exc_or_message,
          backtrace:   [],
          worker_name: worker_name
        )
      end
      fail!
    end

    @@whitelist_paths = ThreadSafe::Array.new

    # Returns the Job to be queued
    def job_class
      return if job_class_name.nil?
      job_class_name.constantize
    rescue NameError
      nil
    end

    # Queues the job for the supplied pathname
    def later(pathname)
      job_class.perform_later(*arguments) do |job|
        job.perform_method = perform_method
        # Set properties
        properties.each_pair { |k, v| job.send("#{k}=".to_sym, v) }

        upload_file(job, pathname)
      end
    end

    protected

    # Upload the file to the job
    def upload_file(job, pathname)
      if job.respond_to?(:file_store_upload)
        # Allow the job to determine what to do with the file
        # Pass the pathname as a string, not a Pathname (IO) instance
        # so that it can read the file directly
        job.file_store_upload(pathname.to_s)
        archive_directory ? archive_file(job, pathname) : pathname.unlink
      elsif job.respond_to?(:upload)
        # With RocketJob Pro the file can be uploaded directly into the Job itself
        job.upload(pathname.to_s)
        archive_directory ? archive_file(job, pathname) : pathname.unlink
      else
        upload_default(job, pathname)
      end
    end

    # Archives the file for a job where there was no #file_store_upload or #upload method
    def upload_default(job, pathname)
      # The first argument must be a hash
      job.arguments << {} if job.arguments.size == 0
      job.arguments.first[:full_file_name] = archive_file(job, pathname)
    end

    # Move the file to the archive directory
    #
    # The archived file name is prefixed with the job id
    #
    # Returns [String] the fully qualified archived file name
    #
    # Note:
    # - Works across partitions when the file and the archive are on different partitions
    def archive_file(job, pathname)
      target_path = archive_pathname
      target_path.mkpath
      target_file_name = target_path.join("#{job.id}_#{pathname.basename}")
      # In case the file is being moved across partitions
      FileUtils.move(pathname.to_s, target_file_name.to_s)
      target_file_name.to_s
    end

  end
end

require 'concurrent'
require 'pathname'
require 'fileutils'
module RocketJob
  class DirmonEntry
    include Plugins::Document
    include Plugins::StateMachine

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

    # Current state, as set by the state machine. Do not modify directly.
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

      event :fail, before: :set_exception do
        transitions from: :enabled, to: :failed
      end
    end

    # @formatter:on
    validates_presence_of :pattern, :job_class_name

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
      if klass = record.job_class
        count = klass.rocket_job_argument_count
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
      collection.aggregate([
        {
          '$group' => {
            _id:   '$state',
            count: {'$sum' => 1}
          }
        }
      ]
      ).each do |result|
        counts[result['_id']] = result['count']
      end
      counts
    end

    # The default archive directory that is used when the job being queued does not respond
    # to #upload, and does not have an `archive_directory` specified in this entry
    cattr_accessor :default_archive_directory

    @@default_archive_directory = '_archive'.freeze

    # Returns [Pathname] the archive_directory if set, otherwise the default_archive_directory
    # Creates the archive directory if one is set
    def archive_pathname(file_pathname)
      if archive_directory
        path = Pathname.new(archive_directory)
        begin
          path.mkpath unless path.exist?
        rescue Errno::ENOENT => exc
          raise(Errno::ENOENT, "DirmonJob failed to create archive directory: #{path}, #{exc.message}")
        end
        path.realpath
      else
        file_pathname.dirname.join(self.class.default_archive_directory).realdirpath
      end
    end

    # Passes each filename [Pathname] found that matches the pattern into the supplied block
    def each(&block)
      logger.fast_tag("DirmonEntry:#{id}") do
        # Case insensitive filename matching
        Pathname.glob(pattern, File::FNM_CASEFOLD).each do |pathname|
          next if pathname.directory?
          pathname  = pathname.realpath
          file_name = pathname.to_s

          # Skip archive directories
          next if file_name.include?(self.class.default_archive_directory)

          # Security check?
          if (whitelist_paths.size > 0) && whitelist_paths.none? { |whitepath| file_name.start_with?(whitepath) }
            logger.error "Skipping file: #{file_name} since it is not in any of the whitelisted paths: #{whitelist_paths.join(', ')}"
            next
          end

          # File must be writable so it can be removed after processing
          unless pathname.writable?
            logger.error "Skipping file: #{file_name} since it is not writable by the current user. Must be able to delete/move the file after queueing the job"
            next
          end
          block.call(pathname)
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
          class_name:  'RocketJob::DirmonEntryException',
          message:     exc_or_message,
          backtrace:   [],
          worker_name: worker_name
        )
      end
    end

    @@whitelist_paths = Concurrent::Array.new

    # Returns the Job to be queued
    def job_class
      return if job_class_name.nil?
      job_class_name.constantize
    rescue NameError
      nil
    end

    # Queues the job for the supplied pathname
    def later(pathname)
      if klass = job_class
        logger.benchmark_info "Enqueued: #{name}, Job class: #{job_class_name}" do
          job = klass.new(properties.merge(arguments: arguments))
          upload_file(job, pathname)
          job.save!
          job
        end
      else
        raise(ArgumentError, "Cannot instantiate a class for: #{job_class_name.inspect}")
      end
    end

    private

    # Instance method to return whitelist paths
    def whitelist_paths
      @@whitelist_paths
    end

    # Upload the file to the job
    def upload_file(job, pathname)
      if job.respond_to?(:upload)
        # With RocketJob Pro the file can be uploaded directly into the Job itself
        job.upload(pathname.to_s)
        archive_directory ? archive_file(job, pathname) : pathname.unlink
      else
        upload_default(job, pathname)
      end
    end

    # Archives the file for a job where there was no #upload method
    def upload_default(job, pathname)
      full_file_name = archive_file(job, pathname)
      if job.respond_to?(:upload_file_name=)
        job.upload_file_name = full_file_name
      elsif job.respond_to?(:full_file_name=)
        job.full_file_name = full_file_name
      elsif job.arguments.first.is_a?(Hash)
        job.arguments.first[:full_file_name] = full_file_name
      else
        raise(ArgumentError, "#{job_class_name} must either have attribute 'upload_file_name' or the first argument must be a Hash")
      end
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
      target_path = archive_pathname(pathname)
      target_path.mkpath
      target_file_name = target_path.join("#{job.id}_#{pathname.basename}")
      # In case the file is being moved across partitions
      FileUtils.move(pathname.to_s, target_file_name.to_s)
      target_file_name.to_s
    end

  end
end

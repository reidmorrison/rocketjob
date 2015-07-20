require 'fileutils'
module RocketJob
  module Jobs
    # Dirmon monitors folders for files matching the criteria specified in DirmonEntry
    #
    # * The first time Dirmon runs it gathers the names of files in the monitored
    #   folders.
    # * On completion Dirmon kicks off a new Dimon job passing it the list
    #   of known files.
    # * On each subsequent Dirmon run it checks the size of each file against the
    #   previous list of known files, and only of the file size has not changed
    #   the corresponding job is started for that file.
    # * If the job implements #file_store_upload or #upload, that method is called
    #   and then the file is deleted, or moved to the archive_directory if supplied
    # * Otherwise, the file is moved to the supplied archive_directory (defaults to
    #   `_archive` in the same folder as the file itself. The absolute path and
    #   file name of the archived file is passed into the job as it's first argument.
    #   Note: This means that such jobs _must_ have a Hash as the first agrument
    #
    # With RocketJob Pro, the file is automatically uploaded into the job itself
    # using the job's #upload method, after which the file is archived or deleted
    # if no archive_directory was specified in the DirmonEntry.
    #
    # To start Dirmon for the first time
    #
    #
    # Note:
    #   Do _not_ start multiple copies of Dirmon as it will result in duplicate
    #   jobs being started.
    class DirmonJob < RocketJob::Job
      DEFAULT_ARCHIVE_DIR = '_archive'.freeze

      rocket_job do |job|
        job.priority = 40
      end

      # Number of seconds between directory scans. Default 5 mins
      key :check_seconds,         Float, default: 300.0

      # TODO Make :perform_later, :perform_now, :perform, :now protected/private
      #      class << self
      #        # Ensure that only one instance of the job is running.
      #        protected :perform_later, :perform_now, :perform, :now
      #      end
      #self.send(:protected, :perform_later)

      # Start the single instance of this job
      # Returns true if the job was started
      # Returns false if the job is already running and doe not need to be started
      def self.start(&block)
        # Prevent multiple Dirmon Jobs from running at the same time
        return false if where(state: [ :running, :queued ]).count > 0

        perform_later({}, &block)
        true
      end

      # Iterate over each Dirmon entry looking for new files
      # If a new file is found, it is not processed immediately, instead
      # it is passed to the next run of this job along with the file size.
      # If the file size has not changed, the Job is kicked off.
      def perform(previous_file_names={})
        new_file_names = check_directories(previous_file_names)
      ensure
        # Run again in the future, even if this run fails with an exception
        self.class.perform_later(new_file_names || previous_file_names) do |job|
          job.priority      = priority
          job.check_seconds = check_seconds
          job.run_at        = Time.now + check_seconds
        end
      end

      # Checks the directories for new files, starting jobs if files have not changed
      # since the last run
      def check_directories(previous_file_names)
        new_file_names = {}
        DirmonEntry.where(enabled: true).each do |entry|
          logger.tagged("Entry:#{entry.id}") do
            Dir[entry.path].each do |file_name|
              next if File.directory?(file_name)
              next if file_name.include?(DEFAULT_ARCHIVE_DIR)
              # BSON Keys cannot contain periods
              key = file_name.gsub('.', '_')
              previous_size = previous_file_names[key]
              if size = check_file(entry, file_name, previous_size)
                new_file_names[key] = size
              end
            end
          end
        end
        new_file_names
      end

      # Checks if a file should result in starting a job
      # Returns [Integer] file size, or nil if the file started a job
      def check_file(entry, file_name, previous_size)
        size = File.size(file_name)
        if previous_size && (previous_size == size)
          logger.info("File stabilized: #{file_name}. Starting: #{entry.job}")
          start_job(entry, file_name)
          nil
        else
          logger.info("Found file: #{file_name}. File size: #{size}")
          # Keep for the next run
          size
        end
      rescue Errno::ENOENT => exc
        # File may have been deleted since the scan was performed
        nil
      end

      # Starts the job for the supplied entry
      def start_job(entry, file_name)
        entry.job.constantize.perform_later(*entry.arguments) do |job|
          # Set properties, also allows :perform_method to be overridden
          entry.properties.each_pair { |k, v| job.send("#{k}=".to_sym, v) }

          upload_file(job, file_name, entry.archive_directory)
        end
      end

      # Upload the file to the job
      def upload_file(job, file_name, archive_directory)
        if job.respond_to?(:file_store_upload)
          # Allow the job to determine what to do with the file
          job.file_store_upload(file_name)
          archive_file(file_name, archive_directory)
        elsif job.respond_to?(:upload)
          # With RocketJob Pro the file can be uploaded directly into the Job itself
          job.upload(file_name)
          archive_file(file_name, archive_directory)
        else
          upload_default(job, file_name, archive_directory)
        end
      end

      # Archives the file for a job where there was no #file_store_upload or #upload method
      def upload_default(job, file_name, archive_directory)
        # The first argument must be a hash
        job.arguments << {} if job.arguments.size == 0
        # If no archive directory is supplied, use DEFAULT_ARCHIVE_DIR under the same path as the file
        archive_directory ||= File.join(File.dirname(file_name), DEFAULT_ARCHIVE_DIR)
        file_name = File.join(archive_directory, File.basename(file_name))
        job.arguments.first[:full_file_name] = File.absolute_path(file_name)
        archive_file(file_name, archive_directory)
      end

      # Move the file to the archive directory
      # Or, delete it if no archive directory was supplied for this entry
      #
      # If the file_name contains a relative path the relative path will be
      # created in the archive_directory before moving the file.
      #
      # If an absolute path is supplied, then the file is just moved into the
      # archive directory without any sub-directories
      def archive_file(file_name, archive_directory)
        # Move file to archive directory if set
        if archive_directory
          # Absolute path?
          target_file_name = if file_name.start_with?('/')
            File.join(archive_directory, File.basename(file_name))
          else
            File.join(archive_directory, file_name)
          end
          FileUtils.mkdir_p(File.dirname(target_file_name))
          FileUtils.move(file_name, target_file_name)
        else
          File.delete(file_name)
        end
      end

    end
  end
end

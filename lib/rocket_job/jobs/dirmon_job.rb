require "fileutils"
module RocketJob
  module Jobs
    # Dirmon monitors folders for files matching the criteria specified in DirmonEntry
    #
    # * The first time Dirmon runs it gathers the names of files in the monitored
    #   folders.
    # * On completion Dirmon kicks off a new Dirmon job passing it the list
    #   of known files.
    # * On each subsequent Dirmon run it checks the size of each file against the
    #   previous list of known files, and only if the file size has not changed
    #   the corresponding job is started for that file.
    # * If the job implements #upload, that method is called
    #   and then the file is deleted, or moved to the archive_directory if supplied

    # * Otherwise, the file is moved to the supplied archive_directory (defaults to
    #   `_archive` in the same folder as the file itself. The absolute path and
    #   file name of the archived file is passed into the job as either
    #   `upload_file_name` or `full_file_name`.

    # Notes:
    # - Jobs that do not implement #upload _must_ have either `upload_file_name` or `full_file_name` as an attribute.
    #
    # With RocketJob Pro, the file is automatically uploaded into the job itself
    # using the job's #upload method, after which the file is archived or deleted
    # if no archive_directory was specified in the DirmonEntry.
    #
    # To start Dirmon for the first time
    #   RocketJob::Jobs::DirmonJob.create!
    #
    # If another DirmonJob instance is already queued or running, then the create
    # above will fail with:
    #   Validation failed: State Another instance of this job is already queued or running
    #
    # Or to start DirmonJob and ignore errors if already running
    #   RocketJob::Jobs::DirmonJob.create
    class DirmonJob < RocketJob::Job
      # Runs every 5 minutes by default
      self.cron_schedule = "*/5 * * * * UTC"
      self.description   = "Directory Monitor"
      self.priority      = 30

      # Hash[file_name, size]
      field :previous_file_names, type: Hash, default: {}, copy_on_restart: true

      # Checks the directories for new files, starting jobs if files have not changed since the last run.
      def perform
        check_directories
      end

      private

      # Iterate over each Dirmon Entry looking for new files
      # If a new file is found, it is not processed immediately, instead
      # it is passed to the next run of this job along with the file size.
      # If the file size has not changed, the Job is kicked off.
      def check_directories
        new_file_names = {}
        DirmonEntry.enabled.each do |dirmon_entry|
          dirmon_entry.each do |path|
            # Skip file size checking since S3 files are only visible once completely uploaded.
            unless path.partial_files_visible?
              logger.info("File: #{path}. Starting: #{dirmon_entry.job_class_name}")
              dirmon_entry.later(path)
              next
            end

            # BSON Keys cannot contain periods
            key           = path.to_s.tr(".", "_")
            previous_size = previous_file_names[key]
            # Check every few minutes for a file size change before trying to process the file.
            size                = check_file(dirmon_entry, path, previous_size)
            new_file_names[key] = size if size
          end
        end
        self.previous_file_names = new_file_names
      end

      # Checks if a file should result in starting a job
      # Returns [Integer] file size, or nil if the file started a job
      def check_file(dirmon_entry, path, previous_size)
        size = path.size
        if previous_size && (previous_size == size)
          logger.info("File stabilized: #{path}. Starting: #{dirmon_entry.job_class_name}")
          dirmon_entry.later(path)
          nil
        else
          logger.info("Found file: #{path}. File size: #{size}")
          # Keep for the next run
          size
        end
      end
    end
  end
end

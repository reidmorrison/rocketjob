require "fileutils"
module RocketJob
  module Jobs
    # Dirmon monitors folders for files matching the criteria specified in DirmonEntry
    #
    # * Each run finds the files that the pattern of each enabled DirmonEntry matches, and their sizes.
    # * A file whose size has not changed since the previous run is processed. A file in a store that only shows
    #   complete files, such as S3, is processed as soon as it is found.
    # * To process a file it is moved to the entry's archive_directory, which is `archive` in the file's directory by
    #   default, and an UploadFileJob is queued, which creates the entry's job and uploads the archived file into it
    #   with its #upload, or sets its `upload_file_name` or `full_file_name` to the archived file.
    # * When a run finishes, fails or is aborted, the next run is scheduled with the files found and their sizes.
    #
    # Notes:
    # - Jobs that do not implement #upload _must_ have either `upload_file_name` or `full_file_name` as an attribute.
    #
    # To start Dirmon for the first time
    #   RocketJob::Jobs::DirmonJob.create!
    #
    # If another DirmonJob instance with the same cron schedule is already queued, running, failed or paused, then the
    # create above fails validation.
    #
    # Or to start DirmonJob and ignore errors if already running
    #   RocketJob::Jobs::DirmonJob.create
    class DirmonJob < RocketJob::Job
      include RocketJob::Plugins::Cron

      # Runs every 5 minutes by default
      self.cron_schedule = "*/5 * * * * UTC"
      self.description   = "Directory Monitor"
      self.priority      = 30

      # Prevent multiple dirmon jobs from running at the same time by only
      # creating the next instance when this one finishes.
      self.cron_after_start = false

      # Hash[file_name, size]
      field :previous_file_names, type: Hash, default: {}, copy_on_restart: true

      # Checks the directories for new files, starting jobs if files have not changed since the last run.
      def perform
        check_directories
      end

      private

      # Iterates over each enabled Dirmon Entry looking for new files, see #check_entry.
      # A new file is passed to the next run of this job along with its file size, and processed by that run when its
      # size has not changed, except in a store that only shows complete files, such as S3, where it is processed as
      # soon as it is found.
      def check_directories
        new_file_names = {}
        DirmonEntry.enabled.each do |dirmon_entry|
          check_entry(dirmon_entry, new_file_names)
        end
        self.previous_file_names = new_file_names
      end

      def check_entry(dirmon_entry, file_names)
        dirmon_entry.each do |path|
          # Skip file size checking since S3 files are only visible once completely uploaded.
          unless path.partial_files_visible?
            logger.info("File: #{RocketJob.path_display_name(path)}. Starting: #{dirmon_entry.job_class_name}")
            dirmon_entry.later(path)
            next
          end

          # The display name leaves out any credentials, and also the user name, which can select another
          # home directory on the same SFTP server, so the key includes the entry.
          # It is valid UTF-8, so that the key can be saved, and is the same when it is read back on the next run,
          # whichever bytes the file name holds, see DirmonEntry#file_display_name.
          # BSON Keys cannot contain periods
          key           = "#{dirmon_entry.id}:#{dirmon_entry.file_display_name(path)}".tr(".", "_")
          previous_size = previous_file_names[key]
          # Check every few minutes for a file size change before trying to process the file.
          size            = check_file(dirmon_entry, path, previous_size)
          file_names[key] = size if size
        end
        dirmon_entry.storage_available!
      rescue IOStreams::Errors::Unavailable => e
        dirmon_entry.storage_unavailable!(worker_name, e)
      rescue StandardError => e
        logger.error(
          "Dirmon Entry: #{dirmon_entry.id} failed. Moved to `failed` state to prevent processing again without manual intervention.", e
        )
        dirmon_entry.fail(worker_name, e)
        dirmon_entry.save(validate: false)
      end

      # Checks if a file should result in starting a job
      # Returns [Integer] file size, or nil if the file started a job, or no longer exists
      def check_file(dirmon_entry, path, previous_size)
        size = file_size(path)
        return unless size

        if previous_size && (previous_size == size)
          logger.info("File stabilized: #{RocketJob.path_display_name(path)}. Starting: #{dirmon_entry.job_class_name}")
          dirmon_entry.later(path)
          nil
        else
          logger.info("Found file: #{RocketJob.path_display_name(path)}. File size: #{size}")
          # Keep for the next run
          size
        end
      end

      # Returns [Integer] the size of the file, or nil when it was removed after it was found,
      # whichever storage it is on.
      def file_size(path)
        path.size
      rescue IOStreams::Errors::NotFound
        logger.info("Skipping file: #{RocketJob.path_display_name(path)} since it no longer exists")
        nil
      end
    end
  end
end

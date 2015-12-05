require 'fileutils'
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
    # * If the job implements #file_store_upload or #upload, that method is called
    #   and then the file is deleted, or moved to the archive_directory if supplied

    # * Otherwise, the file is moved to the supplied archive_directory (defaults to
    #   `_archive` in the same folder as the file itself. The absolute path and
    #   file name of the archived file is passed into the job as it's first argument.

    # Note:
    # - Jobs that do not implement #file_store_upload or #upload _must_ have a
    #   Hash as the first argument
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
    #   MongoMapper::DocumentNotValid: Validation failed: State Another instance of this job is already queued or running
    #
    # Or to start DirmonJob and ignore errors if already running
    #   RocketJob::Jobs::DirmonJob.create
    class DirmonJob < RocketJob::Job
      # Only allow one DirmonJob instance to be running at a time
      include RocketJob::Concerns::Singleton
      # Start a new job when this one completes, fails, or aborts
      include RocketJob::Concerns::Restart

      rocket_job do |job|
        job.priority = 40
      end

      # Number of seconds between directory scans. Default 5 mins
      key :check_seconds, Float, default: 300.0
      key :previous_file_names, Hash # Hash[file_name, size]

      after_initialize :set_run_at

      # Iterate over each Dirmon entry looking for new files
      # If a new file is found, it is not processed immediately, instead
      # it is passed to the next run of this job along with the file size.
      # If the file size has not changed, the Job is kicked off.
      def perform
        check_directories
      end

      private

      # Set a run_at when a new instance of this job is created
      def set_run_at
        self.run_at = Time.now + check_seconds
      end

      # Checks the directories for new files, starting jobs if files have not changed
      # since the last run
      def check_directories
        new_file_names = {}
        DirmonEntry.where(state: :enabled).each do |entry|
          entry.each do |pathname|
            # BSON Keys cannot contain periods
            key           = pathname.to_s.gsub('.', '_')
            previous_size = previous_file_names[key]
            if size = check_file(entry, pathname, previous_size)
              new_file_names[key] = size
            end
          end
        end
        self.previous_file_names = new_file_names
      end

      # Checks if a file should result in starting a job
      # Returns [Integer] file size, or nil if the file started a job
      def check_file(entry, pathname, previous_size)
        size = pathname.size
        if previous_size && (previous_size == size)
          logger.info("File stabilized: #{pathname}. Starting: #{entry.job_class_name}")
          entry.later(pathname)
          nil
        else
          logger.info("Found file: #{pathname}. File size: #{size}")
          # Keep for the next run
          size
        end
      end

    end
  end
end

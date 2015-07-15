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
    #   and then the file is deleted, or moved to the staging_path if supplied
    # * Otherwise, the file is moved to the supplied staging_path (defaults to
    #   `_stage` in the same folder as the file itself. The absolute path and
    #   file name of the staged file is passed into the job as it's first argument.
    #   Note: This means that such jobs _must_ have a Hash as the first agrument
    #
    # With RocketJob Pro, the file is automatically uploaded into the job itself
    # using the job's #upload method, after which the file is staged or deleted
    # if no staging_path was specified in the DirmonEntry.
    #
    # To start Dirmon for the first time
    #
    #
    # Note:
    #   Do _not_ start multiple copies of Dirmon as it will result in duplicate
    #   jobs being started.
    class DirmonJob < RocketJob::Job
      DEFAULT_STAGING_PATH = '_staging'.freeze

      rocket_job do |job|
        job.priority = 40
      end

      # Number of seconds between directory scans. Default 5 mins
      key :check_seconds,         Float, default: 300.0

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
          Dir[entry.path].each do |file_name|
            next if file_name.include?(DEFAULT_STAGING_PATH)
            previous_size = previous_file_names[file_name]
            if size = check_file(entry, file_name, previous_size)
              new_file_names[file_name] = size
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
          start_job(entry, file_name)
          nil
        else
          # Keep for the next run
          size
        end
      rescue Errno::ENOENT => exc
        # File may have been deleted since the scan was performed
      end

      # Starts the job for the supplied entry
      def start_job(entry, file_name)
        entry.job.constantize.perform_later(*entry.arguments) do |job|
          # Set properties, also allows :perform_method to be overridden
          entry.properties.each_pair { |k, v| job.send("#{k}=".to_sym, v) }

          upload_file(job, file_name, entry.staging_path)
        end
      end

      # Upload the file to the job
      def upload_file(job, file_name, staging_path)
        if job.respond_to?(:file_store_upload)
          # Allow the job to determine what to do with the file
          job.file_store_upload(file_name)
          stage_file(file_name, staging_path)
        elsif job.respond_to?(:upload)
          # With RocketJob Pro the file can be uploaded directly into the Job itself
          job.upload(file_name)
          stage_file(file_name, staging_path)
        else
          upload_default(job, file_name, staging_path)
        end
      end

      # Stages a file for a job where there was no #file_store_upload or #upload method
      def upload_default(job, file_name, staging_path)
        # The first argument must be a hash
        job.arguments << {} if job.arguments.size == 0
        # If no staging path is supplied, use DEFAULT_STAGING_PATH under the same path as the file
        staging_path ||= File.join(File.dirname(file_name), DEFAULT_STAGING_PATH)
        file_name = File.join(staging_path, File.basename(file_name))
        job.arguments.first[:full_file_name] = File.absolute_path(file_name)
        stage_file(file_name, staging_path)
      end

      # Move the file to the staging path
      # Or, delete it if no staging path is supplied
      #
      # If the file_name contains a relative path the relative path will be
      # created in the staging_path before moving the file.
      #
      # If an absolute path is supplied, then the file is just moved into the
      # staging path without any sub-directories
      def stage_file(file_name, staging_path)
        # Move file to staging path if set
        if staging_path
          # Absolute path?
          target_file_name = if file_name.start_with?('/')
            File.join(staging_path, File.basename(file_name))
          else
            File.join(staging_path, file_name)
          end
          FileUtils.mkdir_p(File.dirname(target_file_name))
          FileUtils.move(file_name, target_file_name)
        else
          File.delete(file_name)
        end
      end

      # Prevent multiple Dirmon Jobs from running at the same time
      def before_start
        return if self.class.where(state: [ :running, :queued ]).count == 0
        raise "Another Dirmon instance is already queued or running, cannot start multiple Dirmon Job's at the same time"
      end

    end
  end
end

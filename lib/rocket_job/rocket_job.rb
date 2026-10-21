module RocketJob
  def self.create_indexes
    # Ensure models with indexes are loaded into memory first
    Job.create_indexes
    Server.create_indexes
    DirmonEntry.create_indexes
  end

  # Whether the current process is running inside a Rocket Job server process.
  def self.server?
    @server
  end

  # When running inside a Rocket Job server process, returns
  # true when Rails has been initialized.
  def self.rails?
    @rails
  end

  # When running inside a Rocket Job server process, returns
  # true when running standalone.
  def self.standalone?
    !@rails
  end

  # Shown in place of a path that is not valid, since its credentials cannot be found to leave them out.
  INVALID_PATH_DISPLAY_NAME = "(not a valid path)".freeze

  # Returns [String] the supplied path or url to show, for example in a web interface, without any credentials,
  # such as the user name and password of `sftp://user:password@host/file.csv`, see IOStreams::Path#display_name.
  #
  # A path that is not valid is shown as INVALID_PATH_DISPLAY_NAME, as is one that needs a gem that is not installed
  # in this process, such as an S3 url with options in its query, which IOStreams checks with the AWS SDK.
  def self.path_display_name(path)
    return path if path.blank?

    IOStreams.path(path).display_name
  rescue StandardError, LoadError
    INVALID_PATH_DISPLAY_NAME
  end

  # Returns a human readable duration from the supplied [Float] number of seconds
  def self.seconds_as_duration(seconds)
    return nil unless seconds

    if seconds >= 86_400.0 # 1 day
      "#{(seconds / 86_400).to_i}d #{Time.at(seconds).utc.strftime('%-Hh %-Mm')}"
    elsif seconds >= 3600.0 # 1 hour
      Time.at(seconds).utc.strftime("%-Hh %-Mm")
    elsif seconds >= 60.0 # 1 minute
      Time.at(seconds).utc.strftime("%-Mm %-Ss")
    elsif seconds >= 1.0 # 1 second
      format("%.3fs", seconds)
    else
      duration = seconds * 1000
      if defined? JRuby
        "#{duration.to_i}ms"
      else
        duration < 10.0 ? format("%.3fms", duration) : format("%.1fms", duration)
      end
    end
  end

  # private

  @rails  = false
  @server = false

  def self.server!
    @server = true
  end

  def self.rails!
    @rails = true
  end
end

# Slice is a reserved word in Rails 7, but already being used in RocketJob long before that.
Mongoid.destructive_fields.delete(:slice) if Mongoid.respond_to?(:destructive_fields)

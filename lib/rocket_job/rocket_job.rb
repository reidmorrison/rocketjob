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
  # A value that IOStreams cannot build a path from, such as an SFTP url with a non-ASCII letter or a `[` in its file
  # name, or one that needs a gem that is not installed in this process, such as an S3 url without the aws-sdk-s3 gem,
  # is shown as stored, see .display_text, since a url only holds credentials in its user name, password or query.
  # Unless it holds an `@`, which ends a user name and password, or a `?`, which starts a query, when it is shown as
  # INVALID_PATH_DISPLAY_NAME. An `@` anywhere in it counts, since a url that cannot be built can hold a password with
  # a `/` or a `#`, such as `sftp://user:pa/ss@host/file.csv`.
  def self.path_display_name(path)
    return path if path.blank?

    begin
      IOStreams.path(path).display_name
    rescue StandardError, LoadError
      text = path.to_s
      text.include?("@") || text.include?("?") ? INVALID_PATH_DISPLAY_NAME : display_text(text)
    end
  end

  # Returns [String] the supplied text as valid UTF-8, to show or save, with each byte that is not valid UTF-8, such
  # as in a Latin-1 file name, shown as `\xHH`, the way that IOStreams::Path#display_name shows the name of a local
  # file.
  def self.display_text(text)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8)
    return text if text.valid_encoding?

    text.scrub { |bytes| bytes.unpack("C*").map { |byte| format("\\x%02X", byte) }.join }
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

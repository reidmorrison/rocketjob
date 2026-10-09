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
  # in this process.
  def self.path_display_name(path)
    return path if path.blank?

    IOStreams.path(path).display_name
  rescue StandardError, LoadError
    INVALID_PATH_DISPLAY_NAME
  end

  # Returns [String] the supplied text as valid UTF-8, which is the only text that MongoDB stores, so that it can be
  # saved, displayed and logged.
  #
  # A binary string, such as the body of an HTTP response or a file name from SFTP, is read as UTF-8. A string in
  # another encoding, such as Windows-1252, is converted to UTF-8. Each byte that is still not valid, such as the `é`
  # of a Latin-1 name read as UTF-8, is shown as `\xHH`, so that `caf\xE9.csv` becomes "caf\\xE9.csv".
  def self.valid_utf8(text)
    text = text.to_s
    case text.encoding
    when Encoding::UTF_8
      utf8 = text
    when Encoding::BINARY
      utf8 = text.dup.force_encoding(Encoding::UTF_8)
    else
      text = text.scrub { |bytes| escape_bytes(bytes) } unless text.valid_encoding?
      return text.encode(Encoding::UTF_8, fallback: ->(char) { escape_bytes(char) })
    end
    utf8.valid_encoding? ? utf8 : utf8.scrub { |bytes| escape_bytes(bytes) }
  end

  # Returns [String] each of the supplied bytes as `\xHH`, as `String#inspect` shows a byte that is not valid.
  def self.escape_bytes(bytes)
    bytes.unpack("C*").map { |byte| format("\\x%02X", byte) }.join
  end
  private_class_method :escape_bytes

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

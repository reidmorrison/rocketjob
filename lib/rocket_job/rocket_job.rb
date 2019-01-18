module RocketJob
  def self.create_indexes
    # Ensure models with indexes are loaded into memory first
    Job
    Server
    DirmonEntry
    ::Mongoid::Tasks::Database.create_indexes
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

  # Returns a human readable duration from the supplied [Float] number of seconds
  def self.seconds_as_duration(seconds)
    return nil unless seconds
    if seconds >= 86_400.0 # 1 day
      "#{(seconds / 86_400).to_i}d #{Time.at(seconds).strftime('%-Hh %-Mm')}"
    elsif seconds >= 3600.0 # 1 hour
      Time.at(seconds).strftime('%-Hh %-Mm')
    elsif seconds >= 60.0 # 1 minute
      Time.at(seconds).strftime('%-Mm %-Ss')
    elsif seconds >= 1.0 # 1 second
      format('%.3fs', seconds)
    else
      duration = seconds * 1000
      if defined? JRuby
        "#{duration.to_i}ms"
      else
        duration < 10.0 ? format('%.3fms', duration) : format('%.1fms', duration)
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

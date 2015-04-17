# encoding: UTF-8
module RocketJob
  # Heartbeat
  #
  # Information from the server as at it's last heartbeat
  class JobException
    include MongoMapper::EmbeddedDocument

    # Name of the exception class
    key :class_name,              String

    # Exception message
    key :message,                 String

    # Exception Backtrace [Array<String>]
    key :backtrace,               Array

    # Name of the server on which this exception occurred
    key :server_name,             String

    # The record within which this exception occurred
    key :record_number,           Integer

    # Returns [JobException] built from the supplied exception
    def self.from_exception(exc)
      self.new(
        class_name:  exc.class.name,
        message:     exc.message,
        backtrace:   exc.backtrace || []
      )
    end

  end
end


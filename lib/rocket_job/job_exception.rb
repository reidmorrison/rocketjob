# encoding: UTF-8
module RocketJob
  # Heartbeat
  #
  # Information from the worker as at it's last heartbeat
  class JobException
    include MongoMapper::EmbeddedDocument

    # @formatter:off
    # Name of the exception class
    key :class_name,              String

    # Exception message
    key :message,                 String

    # Exception Backtrace [Array<String>]
    key :backtrace,               Array

    # Name of the worker on which this exception occurred
    key :worker_name,             String

    # The record within which this exception occurred
    key :record_number,           Integer

    # @formatter:on

    # Returns [JobException] built from the supplied exception
    def self.from_exception(exc)
      new(
        class_name: exc.class.name,
        message:    exc.message,
        backtrace:  exc.backtrace || []
      )
    end

  end
end

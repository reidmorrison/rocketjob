# encoding: UTF-8
module RocketJob
  class JobException
    include Plugins::Document

    embedded_in :job, inverse_of: :exception
    embedded_in :slice, inverse_of: :exception
    embedded_in :dirmon_entry, inverse_of: :exception

    # Name of the exception class
    field :class_name, type: String

    # Exception message
    field :message, type: String

    # Exception Backtrace [Array<String>]
    field :backtrace, type: Array, default: []

    # Name of the server on which this exception occurred
    field :worker_name, type: String

    # The record within which this exception occurred
    field :record_number, type: Integer

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

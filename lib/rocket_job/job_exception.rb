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

    # Returns [JobException] built from the supplied exception
    def self.from_exception(exc, **args)
      new(
        args.merge(
          class_name: exc.class.name,
          message:    exc.message.to_s,
          backtrace:  exc.backtrace || []
        )
      )
    end

    # Sets the message as valid UTF-8, see RocketJob.valid_utf8, so that the exception can always be saved, whatever
    # text the failure held, such as a response body that is not UTF-8, or a file name in Latin-1.
    def message=(message)
      super(message.nil? ? nil : RocketJob.valid_utf8(message))
    end

    # Sets each line of the backtrace as valid UTF-8, see #message=.
    def backtrace=(backtrace)
      super(backtrace&.map { |line| RocketJob.valid_utf8(line) })
    end
  end
end

module Compat
  # The outcome of one scenario: what each of its steps returned, such as what was uploaded, what #perform received
  # and what was downloaded, or the error that stopped it, in a form that JSON holds and that compares exactly.
  class Result
    # Returns [String] the exact form of a value, such as a record, that tells a Symbol key from a String key.
    def self.show(value)
      value.inspect
    end

    # Returns [Array] the value of the block and nil, or nil and the error that the block raised, see .error.
    def self.attempt(step)
      [yield, nil]
    rescue Exception => e
      raise if e.is_a?(Interrupt)

      [nil, error(e, step)]
    end

    # Returns [Hash] the supplied exception, as it was raised by the supplied step.
    def self.error(exception, step)
      {
        "step"      => step,
        "class"     => exception.class.name,
        "message"   => exception.message.to_s.encode("UTF-8", invalid: :replace, undef: :replace)[0, 600],
        "backtrace" => (exception.backtrace || []).first(4).map { |line| Capture.short(line) }
      }
    end

    def initialize(**attributes)
      @data = attributes.transform_keys(&:to_s)
    end

    def [](key)
      @data[key.to_s]
    end

    def []=(key, value)
      @data[key.to_s] = value
    end

    # Returns [true|false] whether a step raised, which stops the scenario.
    def failed?
      @data.key?("error")
    end

    # Returns the value of the block, or nil when it raises, when its error becomes the error of this result.
    def step(name, &)
      value, error = self.class.attempt(name, &)
      @data["error"] ||= error if error
      value
    end

    def to_h
      @data
    end
  end
end

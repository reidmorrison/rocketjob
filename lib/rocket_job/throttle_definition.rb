module RocketJob
  class ThrottleDefinition
    attr_reader :method_name, :filter

    def initialize(method_name, filter)
      @method_name = method_name.to_sym
      @filter      = filter
    end

    # Returns [true|false] whether the throttle was triggered.
    def throttled?(job, *args)
      # Throttle exceeded?
      # Throttle methods can be private.
      throttled =
        if args.size.positive?
          job.method(method_name).arity.zero? ? job.send(method_name) : job.send(method_name, *args)
        else
          job.send(method_name)
        end
      return false unless throttled

      job.logger.debug { "Throttle: #{method_name} has been exceeded." }
      true
    rescue Exception => e
      job.logger.error("Throttle failed.", e)
      true
    end

    # Returns the filter to apply to the job when the above throttle returns true.
    def extract_filter(job, *args)
      return filter.call(job, *args) if filter.is_a?(Proc)

      if args.size.positive?
        job.method(filter).arity.zero? ? job.send(filter) : job.send(filter, *args)
      else
        job.send(filter)
      end
    end
  end
end

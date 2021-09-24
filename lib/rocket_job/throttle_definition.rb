module RocketJob
  class ThrottleDefinition
    attr_reader :method_name, :filter, :description

    def initialize(method_name, filter, description)
      @method_name = method_name.to_sym
      @filter      = filter
      @description = description || method_name.to_s
    end

    # Returns [true|false] whether the throttle has been exceeded.
    def throttled?(job, *args)
      # Use `send` since throttling methods could be private.
      throttled =
        if args.size.positive?
          job.method(method_name).arity.zero? ? job.send(method_name) : job.send(method_name, *args)
        else
          job.send(method_name)
        end
      return false unless throttled

      job.logger.debug { "Throttle: #{method_name} has been exceeded." }
      true
    end

    # Returns the filter to apply to the job when this throttle is active.
    def apply_filter(job, *args)
      return filter.call(job, *args) if filter.is_a?(Proc)
      return job.send(filter) unless args.size.positive?

      job.method(filter).arity.zero? ? job.send(filter) : job.send(filter, *args)
    end
  end
end

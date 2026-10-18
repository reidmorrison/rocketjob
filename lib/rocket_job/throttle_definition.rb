module RocketJob
  class ThrottleDefinition
    attr_reader :method_name, :filter, :description

    # Parameters:
    #   description: [String|Proc|nil]
    #     Human readable reason why the job is throttled, persisted to the job as
    #     `throttled_by` and surfaced in Mission Control.
    #     When a Proc, it is called with the same arguments as the throttle and must
    #     return a String, allowing the reason to include runtime detail.
    #     When nil, a humanized version of the method name is used.
    def initialize(method_name, filter, description = nil)
      @method_name = method_name.to_sym
      @filter      = filter
      @description = description
    end

    # Returns [true|false] whether the throttle was triggered.
    def throttled?(job, *args)
      return false unless call_job_method(job, method_name, args)

      job.logger.debug { "Throttle: #{method_name} has been exceeded." }
      true
    end

    # Returns the filter to apply to the job when the above throttle returns true.
    def extract_filter(job, *args)
      return filter.call(job, *args) if filter.is_a?(Proc)

      call_job_method(job, filter, args)
    end

    # Returns [String] the human readable reason why the job is throttled.
    def extract_description(job, *)
      return description.call(job, *) if description.is_a?(Proc)
      return description if description

      # Default: humanize the method name, dropping a trailing `?` or `_exceeded`.
      method_name.to_s.sub(/_exceeded\?\z/, "").sub(/\?\z/, "").tr("_", " ").capitalize
    end

    private

    # Calls the named method of the job, which can be private, with the supplied arguments, such as the slice of a
    # batch throttle, unless it takes none.
    def call_job_method(job, name, args)
      return job.send(name) if args.empty? || job.method(name).arity.zero?

      job.send(name, *args)
    end
  end
end

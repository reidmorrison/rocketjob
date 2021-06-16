module RocketJob
  class ThrottleDefinitions
    attr_accessor :throttles

    def initialize
      @throttles = []
    end

    def add(method_name, filter)
      unless filter.is_a?(Symbol) || filter.is_a?(Proc)
        raise(ArgumentError, "Filter for #{method_name} must be a Symbol or Proc")
      end
      raise(ArgumentError, "Cannot define #{method_name} twice, undefine previous throttle first") if exist?(method_name)

      @throttles += [ThrottleDefinition.new(method_name, filter)]
    end

    # Undefine a previously defined throttle
    def remove(method_name)
      throttles.delete_if { |throttle| throttle.method_name == method_name }
    end

    # Has a throttle been defined?
    def exist?(method_name)
      throttles.any? { |throttle| throttle.method_name == method_name }
    end

    # Returns the matching filter,
    # or nil if no throttles were triggered.
    def matching_filter(job, *args)
      throttles.each do |throttle|
        next unless throttle.throttled?(job, *args)

        return throttle.extract_filter(job, *args)
      end
      nil
    end

    def deep_dup
      new_defination           = dup
      new_defination.throttles = throttles.map(&:dup)
      new_defination
    end
  end
end

module RocketJob
  class ThrottleDefinitions
    attr_accessor :throttles

    def initialize
      @throttles = []
    end

    def add(method_name, filter, description = nil)
      unless filter.is_a?(Symbol) || filter.is_a?(Proc)
        raise(ArgumentError, "Filter for #{method_name} must be a Symbol or Proc")
      end
      raise(ArgumentError, "Cannot define #{method_name} twice, undefine previous throttle first") if exist?(method_name)

      @throttles += [ThrottleDefinition.new(method_name, filter, description)]
    end

    # Undefine a previously defined throttle
    def remove(method_name)
      throttles.delete_if { |throttle| throttle.method_name == method_name }
    end

    # Has a throttle been defined?
    def exist?(method_name)
      throttles.any? { |throttle| throttle.method_name == method_name }
    end

    def deep_dup
      new_definition           = dup
      new_definition.throttles = throttles.map(&:dup)
      new_definition
    end
  end
end

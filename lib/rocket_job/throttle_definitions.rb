module RocketJob
  # The throttles of a job class, in the order that they are checked.
  #
  # A class shares its throttles with its subclasses until one of them defines or undefines a throttle, see #with and
  # #without, which return a changed copy and never change the throttles that they are called on.
  class ThrottleDefinitions
    attr_accessor :throttles

    def initialize
      @throttles = []
    end

    # Returns [ThrottleDefinitions] a copy of these throttles with the supplied throttle added after them, see #add.
    # These throttles are not changed, so that a subclass that adds a throttle does not add it to its parent class.
    def with(method_name, filter, description = nil)
      copy = dup
      copy.add(method_name, filter, description)
      copy
    end

    # Returns [ThrottleDefinitions] a copy of these throttles without the named throttle. These throttles are not
    # changed, so that a subclass that removes a throttle does not remove it from its parent class.
    def without(method_name)
      copy = dup
      copy.remove(method_name)
      copy
    end

    def add(method_name, filter, description = nil)
      unless filter.is_a?(Symbol) || filter.is_a?(Proc)
        raise(ArgumentError, "Filter for #{method_name} must be a Symbol or Proc")
      end
      raise(ArgumentError, "Cannot define #{method_name} twice, undefine previous throttle first") if exist?(method_name)

      @throttles += [ThrottleDefinition.new(method_name, filter, description)]
    end

    # Undefine a previously defined throttle.
    #
    # Replaces the list of throttles rather than removing the throttle from it, since a copy made with `dup` shares
    # the list.
    def remove(method_name)
      @throttles = throttles.reject { |throttle| throttle.method_name == method_name }
    end

    # Has a throttle been defined?
    def exist?(method_name)
      throttles.any? { |throttle| throttle.method_name == method_name }
    end

    # Returns [ThrottleDefinition] the first throttle that was triggered,
    # or nil if no throttles were triggered.
    #
    # The returned definition exposes both the filter (`extract_filter`) and the
    # human readable reason (`extract_description`) so callers can apply the filter
    # and persist why the job was throttled.
    def matching_throttle(job, *args)
      throttles.find { |throttle| throttle.throttled?(job, *args) }
    end

    # Returns the matching filter,
    # or nil if no throttles were triggered.
    def matching_filter(job, *)
      matching_throttle(job, *)&.extract_filter(job, *)
    end

    def deep_dup
      new_defination           = dup
      new_defination.throttles = throttles.map(&:dup)
      new_defination
    end
  end
end

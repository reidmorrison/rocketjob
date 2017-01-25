require 'aasm'

# The following patches can be removed once the following PR has been merged into AASM:
#   https://github.com/aasm/aasm/pull/269

AASM::Core::Event
module AASM::Core
  class Event
    def initialize_copy(orig)
      super
      @transitions = @transitions.collect { |transition| transition.clone }
      @guards      = @guards.dup
      @unless      = @unless.dup
      @options     = {}
      orig.options.each_pair { |name, setting| @options[name] = setting.is_a?(Hash) || setting.is_a?(Array) ? setting.dup : setting }
    end
  end
end

AASM::Core::State
module AASM::Core
  class State
    # called internally by Ruby 1.9 after clone()
    def initialize_copy(orig)
      super
      @options = {}
      orig.options.each_pair { |name, setting| @options[name] = setting.is_a?(Hash) || setting.is_a?(Array) ? setting.dup : setting }
    end
  end
end

AASM::Core::Transition
module AASM::Core
  class Transition
    def initialize_copy(orig)
      super
      @guards = @guards.dup
      @unless = @unless.dup
      @opts   = {}
      orig.opts.each_pair { |name, setting| @opts[name] = setting.is_a?(Hash) || setting.is_a?(Array) ? setting.dup : setting }
    end
  end
end

AASM::StateMachine
module AASM
  class StateMachine
    def initialize_copy(orig)
      super
      @states = orig.states.collect { |state| state.clone }
      @events = {}
      orig.events.each_pair { |name, event| @events[name] = event.clone }
      @global_callbacks = @global_callbacks.dup
    end
  end
end

# Patch to try and make AASM threadsafe
AASM::StateMachineStore
module AASM
  class StateMachineStore
    @stores = Concurrent::Map.new

    def self.stores
      @stores
    end

    def initialize
      @machines = Concurrent::Map.new
    end
  end
end

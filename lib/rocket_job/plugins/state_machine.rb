require "active_support/concern"
require "aasm"

module RocketJob
  module Plugins
    # State machine for RocketJob
    #
    # Define before and after callbacks for state machine events
    #
    # Example: Supply a method name to call
    #
    #  class MyJob < RocketJob::Job
    #    before_fail :let_me_know
    #
    #    def let_me_know
    #      puts "Oh no, the job has failed with and exception"
    #    end
    #  end
    #
    # Example: Pass a block
    #
    #  class MyJob < RocketJob::Job
    #    before_fail do
    #      puts "Oh no, the job has failed with an exception"
    #    end
    #  end
    module StateMachine
      extend ActiveSupport::Concern

      included do
        include AASM

        # Adds a :before or :after callback to an event
        #  state_machine_add_event_callback(:start, :before, :my_method)
        def self.state_machine_add_event_callback(event_name, action, *methods, &block)
          raise(ArgumentError, "Cannot supply both a method name and a block") if methods.size.positive? && block
          raise(ArgumentError, "Must supply either a method name or a block") unless methods.size.positive? || block

          # Limitation with AASM. It only supports guards on event transitions, not for callbacks.
          # For example, AASM does not support callback options such as :if and :unless, yet Rails callbacks do.
          #    before_start :my_callback, unless: :encrypted?
          #    before_start :my_callback, if: :encrypted?
          event = aasm.state_machine.events[event_name]
          raise(ArgumentError, "Unknown event: #{event_name.inspect}") unless event

          values = Array(event.options[action])
          code   =
            if block
              block
            else
              # Validate methods are any of Symbol String Proc
              methods.each do |method|
                unless method.is_a?(Symbol) || method.is_a?(String)
                  raise(ArgumentError,
                        "#{action}_#{event_name} currently does not support any options. Only Symbol and String method names can be supplied.")
                end
              end
              methods
            end
          action == :before ? values.push(code) : values.unshift(code)
          event.options[action] = values.flatten.uniq
        end

        def self.state_machine_define_event_callbacks(*event_names)
          event_names.each do |event_name|
            module_eval <<-RUBY, __FILE__, __LINE__ + 1
              def self.before_#{event_name}(*methods, &block)
                state_machine_add_event_callback(:#{event_name}, :before, *methods, &block)
              end

              def self.after_#{event_name}(*methods, &block)
               state_machine_add_event_callback(:#{event_name}, :after, *methods, &block)
              end
            RUBY
          end
        end
      end
    end
  end
end

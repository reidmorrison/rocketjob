# encoding: UTF-8
require 'active_support/concern'
require 'aasm'
require 'rocket_job/extensions/aasm'

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
          raise(ArgumentError, 'Cannot supply both a method name and a block') if (methods.size > 0) && block
          raise(ArgumentError, 'Must supply either a method name or a block') unless (methods.size > 0) || block

          if event = aasm.state_machine.events[event_name]
            values = Array(event.options[action])
            code = block ? block : methods
            action == :before ? values.push(code) : values.unshift(code)
            event.options[action] = values.flatten.uniq
          else
            raise(ArgumentError, "Unknown event: #{event_name.inspect}")
          end
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

        # Patch AASM so that save! is called instead of save
        # So that validations are run before job.requeue! is completed
        # Otherwise it just fails silently
        def aasm_write_state(state, name=:default)
          attr_name = self.class.aasm(name).attribute_name
          old_value = read_attribute(attr_name)
          write_attribute(attr_name, state)

          begin
            if aasm_skipping_validations(name)
              saved = save(validate: false)
              write_attribute(attr_name, old_value) unless saved
              saved
            else
              save!
            end
          rescue Exception => exc
            write_attribute(attr_name, old_value)
            raise(exc)
          end
        end
      end

    end
  end
end

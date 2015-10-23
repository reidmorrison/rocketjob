# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Concerns
    # Define before and after callbacks
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
    module EventCallbacks
      extend ActiveSupport::Concern

      included do

        # Adds a :before or :after callback to an event
        #  add_event_callback(:start, :before, :my_method)
        def self.add_event_callback(event_name, action, *methods, &block)
          raise(ArgumentError, 'Cannot supply both a method name and a block') if (methods.size > 0) && block
          raise(ArgumentError, 'Must supply either a method name or a block') unless (methods.size > 0) || block

          if event = aasm.state_machine.events[event_name]
            values = Array(event.options[action])
            values << (block ? block : methods)
            event.options[action] = values.flatten.uniq
          else
            raise(ArgumentError, "Unknown event: #{event_name.inspect}")
          end
        end

        def self.define_event_callbacks(*event_names)
          event_names.each do |event_name|
            module_eval <<-RUBY, __FILE__, __LINE__ + 1
              def self.before_#{event_name}(*methods, &block)
                add_event_callback(:#{event_name}, :before, *methods, &block)
              end

              def self.after_#{event_name}(*methods, &block)
               add_event_callback(:#{event_name}, :after, *methods, &block)
              end
            RUBY
          end
        end

      end

    end
  end
end

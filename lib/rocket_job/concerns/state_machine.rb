# encoding: UTF-8
require 'active_support/concern'
require 'aasm'
require 'rocket_job/extensions/aasm'

module RocketJob
  module Concerns
    # State machine for RocketJob
    module StateMachine
      extend ActiveSupport::Concern

      included do
        include AASM

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

module Compat
  # Defines the batch job class of a scenario under Compat, with the input and output categories that the scenario
  # declares, the way an application declares them, and a #perform that records each record that it receives, as it
  # receives it, see .received, then returns the scenario's transform of the record, or the record itself.
  module JobFactory
    # Returns [Class] the job class, which replaces a class of the same name, so that a scenario can be run again.
    def self.define(name, input:, outputs:, transform:)
      Compat.send(:remove_const, name) if Compat.const_defined?(name, false)
      klass = Compat.const_set(name, Class.new(RocketJob::Job))
      # Mongoid registers the class of each `_type` by the name that the class has when it is defined, which an
      # anonymous class does not have yet, so it is registered here, otherwise a saved job could not be loaded again.
      klass.discriminator_value = klass.name
      klass.include(RocketJob::Batch)
      klass.include(Perform)
      klass.extend(Records)
      klass.destroy_on_complete = false
      klass.transform           = transform
      klass.input_category(**input) if input
      outputs&.each { |output| klass.output_category(**output) }
      klass
    end

    # The #perform of each job class.
    module Perform
      def perform(record)
        self.class.received << Result.show(record)
        transform = self.class.transform
        transform ? transform.call(record) : record
      end
    end

    # What each job class knows: its transform, and the records that its jobs received.
    module Records
      attr_accessor :transform

      # Returns [Array<String>] each record that #perform received, see Result.show.
      def received
        @received ||= []
      end
    end
  end
end

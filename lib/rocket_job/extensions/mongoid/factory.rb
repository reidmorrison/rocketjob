require 'mongoid/factory'

module RocketJob
  module Mongoid
    module Factory
      def from_db(*args)
        super(*args)
      rescue NameError
        RocketJob::Job.instantiate(attributes, selected_fields)
      end
    end
  end
end

::Mongoid::Factory.extend(RocketJob::Mongoid::Factory)

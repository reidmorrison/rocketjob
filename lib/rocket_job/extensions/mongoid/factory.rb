require 'mongoid/factory'

module RocketJob
  # Don't convert to Mongoid::Factory since it conflicts with Mongoid use.
  module MongoidFactory
    def from_db(klass, attributes = nil, selected_fields = nil)
      super
    rescue NameError
      RocketJob::Job.instantiate(attributes, selected_fields)
    end
  end
end

::Mongoid::Factory.extend(RocketJob::MongoidFactory)

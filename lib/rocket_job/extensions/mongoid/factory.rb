require 'mongoid/factory'

module RocketJob
  module MongoidFactory
    def from_db(*args)
      super(*args)
    rescue NameError
      RocketJob::Job.instantiate(attributes, selected_fields)
    end
  end
end

::Mongoid::Factory.include(RocketJob::MongoidFactory)

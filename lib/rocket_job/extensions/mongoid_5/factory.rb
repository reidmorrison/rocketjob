require 'mongoid/factory'

module RocketJob
  module Mongoid5Factory
    def from_db(klass, attributes = nil, selected_fields = nil, criteria = nil)
      obj                 = super(klass, attributes, selected_fields)
      obj.collection_name = criteria.collection_name if criteria
      obj
    end
  end
end

::Mongoid::Factory.extend(RocketJob::Mongoid5Factory)

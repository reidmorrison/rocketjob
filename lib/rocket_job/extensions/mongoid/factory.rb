require "mongoid/factory"

module RocketJob
  # Don't convert to Mongoid::Factory since it conflicts with Mongoid use.
  module MongoidFactory
    def from_db(klass, attributes = nil, criteria = nil, selected_fields = nil)
      obj                 = super(klass, attributes, criteria, selected_fields)
      obj.collection_name = criteria.collection_name if criteria
      obj
    end
  end
end

::Mongoid::Factory.extend(RocketJob::MongoidFactory)

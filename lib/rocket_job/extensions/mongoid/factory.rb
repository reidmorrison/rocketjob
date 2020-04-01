require "mongoid/factory"

module RocketJob
  # Don't convert to Mongoid::Factory since it conflicts with Mongoid use.
  module MongoidFactory
    if Mongoid::VERSION.to_f >= 7.1
      def from_db(klass, attributes = nil, criteria = nil, selected_fields = nil)
        obj                 = super(klass, attributes, criteria, selected_fields)
        obj.collection_name = criteria.collection_name if criteria
        obj
      end
    else
      def from_db(klass, attributes = nil, criteria = nil)
        obj                 = super(klass, attributes, criteria)
        obj.collection_name = criteria.collection_name if criteria
        obj
      end
    end
  end
end

::Mongoid::Factory.extend(RocketJob::MongoidFactory)

::Mongoid::Contextual::Mongo
module Mongoid
  module Contextual
    class Mongo
      def initialize(criteria)
        @criteria = criteria
        @klass    = criteria.klass
        @cache    = criteria.options[:cache]
        # Only line changed is here, get collection name from criteria, not @klass
        # @collection = @klass.collection
        @collection = criteria.collection

        criteria.send(:merge_type_selection)
        @view = collection.find(criteria.selector, session: _session)
        apply_options
      end
    end
  end
end

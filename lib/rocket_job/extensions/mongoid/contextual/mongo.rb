module Mongoid
  module Contextual
    class Mongo
      def initialize(criteria)
        @criteria = criteria
        @klass    = criteria.klass
        # Only line changed from the Mongoid implementation is here: fetch the
        # collection from the criteria so a custom collection_name is honored
        # rather than always using @klass.collection.
        # @collection = @klass.collection
        @collection = criteria.collection
        criteria.send(:merge_type_selection)
        @view = collection.find(criteria.selector, session: _session)
        apply_options
      end
    end
  end
end

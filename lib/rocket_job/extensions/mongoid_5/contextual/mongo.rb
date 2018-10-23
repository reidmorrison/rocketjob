::Mongoid::Contextual::Mongo
module Mongoid
  module Contextual
    class Mongo
      def initialize(criteria)
        @criteria, @klass, @cache = criteria, criteria.klass, criteria.options[:cache]

        # Only line changed is here, get collection name from criteria, not @klass
        #@collection = @klass.with(criteria.persistence_options || {}).collection
        @collection = criteria.collection

        criteria.send(:merge_type_selection)
        @view = collection.find(criteria.selector)
        apply_options
      end

      #
      # Patches below add `criteria` as the last argument to `Factory.from_db`
      #
      def first
        return documents.first if cached? && cache_loaded?
        try_cache(:first) do
          if raw_doc = view.limit(-1).first
            doc = Factory.from_db(klass, raw_doc, criteria.options[:fields], criteria)
            eager_load([doc]).first
          end
        end
      end

      def find_first
        return documents.first if cached? && cache_loaded?
        if raw_doc = view.first
          doc = Factory.from_db(klass, raw_doc, criteria.options[:fields], criteria)
          eager_load([doc]).first
        end
      end

      def last
        try_cache(:last) do
          with_inverse_sorting do
            if raw_doc = view.limit(-1).first
              doc = Factory.from_db(klass, raw_doc, criteria.options[:fields], criteria)
              eager_load([doc]).first
            end
          end
        end
      end

      def documents_for_iteration
        return documents if cached? && !documents.empty?
        return view unless eager_loadable?
        docs = view.map{ |doc| Factory.from_db(klass, doc, criteria.options[:fields], criteria) }
        eager_load(docs)
      end

      def yield_document(document, &block)
        doc = document.respond_to?(:_id) ?
                document : Factory.from_db(klass, document, criteria.options[:fields], criteria)
        yield(doc)
        documents.push(doc) if cacheable?
      end
    end
  end
end

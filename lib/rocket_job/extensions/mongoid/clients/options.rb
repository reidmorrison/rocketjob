require "mongoid/criteria"
require "mongoid/document"
module RocketJob
  module MongoidClients
    module Options
      extend ActiveSupport::Concern

      def with_collection(collection_name)
        self.collection_name = collection_name
        self
      end

      def collection(parent = nil)
        @collection_name ? mongo_client[@collection_name] : super(parent)
      end

      def collection_name
        @collection_name || super
      end

      def collection_name=(collection_name)
        @collection_name = collection_name&.to_sym
      end

      private

      module ClassMethods
        def with_collection(collection_name)
          all.with_collection(collection_name)
        end
      end
    end
  end
end

::Mongoid::Criteria.include(RocketJob::MongoidClients::Options)
::Mongoid::Document.include(RocketJob::MongoidClients::Options)

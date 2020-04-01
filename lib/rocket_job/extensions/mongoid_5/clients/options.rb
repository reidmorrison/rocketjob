require "mongoid/criteria"
require "mongoid/document"
module RocketJob
  module Mongoid5Clients
    module Options
      extend ActiveSupport::Concern

      def with_collection(collection_name)
        self.collection_name = collection_name
        self
      end

      def collection
        return (@klass || self.class).with(persistence_options || {}).collection unless @collection_name

        (@klass || self.class).mongo_client[@collection_name]
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

::Mongoid::Criteria.include(RocketJob::Mongoid5Clients::Options)
::Mongoid::Document.include(RocketJob::Mongoid5Clients::Options)

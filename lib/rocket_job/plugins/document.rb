require "active_support/concern"

module RocketJob
  module Plugins
    # Base class for storing models in MongoDB
    module Document
      extend ActiveSupport::Concern
      include ::Mongoid::Document

      included do
        store_in client: "rocketjob"
      end

      # rubocop:disable Style/RedundantSort
      module ClassMethods
        # Mongoid does not apply ordering, add sort
        def first
          all.sort("_id" => 1).first
        end

        # Mongoid does not apply ordering, add sort
        def last
          all.sort("_id" => -1).first
        end
      end
      # rubocop:enable Style/RedundantSort

      private

      # Apply changes to this document returning the updated document from the database.
      # Allows other changes to be made on the server that will be loaded.
      def find_and_update(attrs)
        doc = collection.find(_id: id).find_one_and_update({"$set" => attrs}, return_document: :after)
        raise(::Mongoid::Errors::DocumentNotFound.new(self.class, id)) unless doc

        # Clear out keys that are not returned during the reload from MongoDB
        (fields.keys + embedded_relations.keys - doc.keys).each { |key| send("#{key}=", nil) }
        @attributes = doc
        apply_defaults
        self
      end
    end
  end
end

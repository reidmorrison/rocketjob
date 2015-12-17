# encoding: UTF-8
require 'active_support/concern'
require 'mongo'
require 'mongo_ha'
require 'mongo_mapper'

module RocketJob
  module Concerns
    # Prevent more than one instance of this job class from running at a time
    module Document
      extend ActiveSupport::Concern
      include MongoMapper::Document

      included do
        # Add after_initialize & after_find callbacks
        define_model_callbacks :initialize, :find, :only => [:after]

        # Prevent data in MongoDB from re-defining the model behavior
        #self.static_keys = true
      end

      # Patch the way MongoMapper reloads a model
      def reload
        if doc = collection.find_one(:_id => id)
          # Clear out keys that are not returned during the reload from MongoDB
          (keys.keys - doc.keys).each { |key| send("#{key}=", nil) }
          initialize_default_values
          load_from_database(doc)
          self
        else
          raise MongoMapper::DocumentNotFound, "Document match #{_id.inspect} does not exist in #{collection.name} collection"
        end
      end

      # Add after_initialize callbacks
      # TODO: Remove after new MongoMapper gem is released
      #       Also remove define_model_callbacks above
      def initialize(*)
        run_callbacks(:initialize) { super }
      end

      def initialize_from_database(*)
        run_callbacks(:initialize) do
          run_callbacks(:find) do
            super
          end
        end
      end

      private

      def update_attributes_and_reload(attrs)
        if doc = self.class.find_and_modify(query: {:_id => id}, update: {'$set' => attrs})
          # Clear out keys that are not returned during the reload from MongoDB
          (keys.keys - doc.keys).each { |key| send("#{key}=", nil) }
          initialize_default_values
          load_from_database(doc)
          self
        else
          raise MongoMapper::DocumentNotFound, "Document match #{_id.inspect} does not exist in #{collection.name} collection"
        end
      end

    end
  end
end

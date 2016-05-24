# encoding: UTF-8
require 'active_support/concern'
require 'mongo'
require 'mongo_ha'
require 'mongo_mapper'

module RocketJob
  module Plugins
    # Base class for storing models in MongoDB
    module Document
      autoload :Static, 'rocket_job/plugins/document/static'

      extend ActiveSupport::Concern
      include MongoMapper::Document
      include RocketJob::Plugins::Document::Static

      included do
        # Prevent data in MongoDB from re-defining the model behavior
        self.static_keys     = true

        # Turn off embedded callbacks. Slow and not used for Jobs
        embedded_callbacks_off
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

      private

      def update_attributes_and_reload(attrs)
        if doc = collection.find_and_modify(query: {:_id => id}, update: {'$set' => attrs})
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

# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Plugins
    # Base class for storing models in MongoDB
    module Document
      extend ActiveSupport::Concern
      include Mongoid::Document

      module ClassMethods
        # Defines all the fields that are accessible on the Document
        # For each field that is defined, a getter and setter will be
        # added as an instance method to the Document.
        #
        # @example Define a field.
        #   field :score, :type => Integer, :default => 0
        #
        # @param [ Symbol ] name The name of the field.
        # @param [ Hash ] options The options to pass to the field.
        #
        # @option options [ Class ] :type The type of the field.
        # @option options [ String ] :label The label for the field.
        # @option options [ Object, Proc ] :default The field's default
        # @option options [ Boolean ] :class_attribute Keep the fields default in a class_attribute
        #
        # @return [ Field ] The generated field
        def field(name, options)
          if options.delete(:class_attribute) == true
            class_attribute(name, instance_accessor: false)
            if default = options[:default]
              public_send("#{name}=", default)
            end
            options[:default] = lambda { self.class.public_send(name) }
          end
          super(name, options)
        end

        # V2 Backward compatibility
        # DEPRECATED
        def key(name, type, options = {})
          field(name, options.merge(type: type))
        end

        # DEPRECATED
        def rocket_job
          raise(NotImplementedError, "Replace calls to .rocket_job with calls to set class instance variables. For example: self.priority = 50")
        end
      end

      private

      # TODO: Need similar capability for Mongoid
      # def update_attributes_and_reload(attrs)
      #   if doc = collection.find_and_modify(query: {:_id => id}, update: {'$set' => attrs})
      #     # Clear out keys that are not returned during the reload from MongoDB
      #     (keys.keys - doc.keys).each { |key| send("#{key}=", nil) }
      #     initialize_default_values
      #     load_from_database(doc)
      #     self
      #   else
      #     raise MongoMapper::DocumentNotFound, "Document match #{_id.inspect} does not exist in #{collection.name} collection"
      #   end
      # end

    end
  end
end

# encoding: UTF-8
require 'active_support/concern'

module RocketJob
  module Plugins
    # Base class for storing models in MongoDB
    module Document
      extend ActiveSupport::Concern
      include Mongoid::Document

      included do
        store_in client: 'rocketjob'

        class_attribute :user_editable_fields, instance_accessor: false
        self.user_editable_fields = []
      end

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
        # @option options [ Boolean ] :user_editable Field can be edited by end users in RJMC
        #
        # @return [ Field ] The generated field
        def field(name, options)
          if options.delete(:user_editable) == true
            self.user_editable_fields += [name.to_sym] unless user_editable_fields.include?(name.to_sym)
          end
          if options.delete(:class_attribute) == true
            class_attribute(name, instance_accessor: false)
            if options.has_key?(:default)
              public_send("#{name}=", options[:default])
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

        # Mongoid does not apply ordering, add sort
        def first
          all.sort('_id' => 1).first
        end

        # Mongoid does not apply ordering, add sort
        def last
          all.sort('_id' => -1).first
        end
      end

      private

      # Apply changes to this document returning the updated document from the database.
      # Allows other changes to be made on the server that will be loaded.
      def find_and_update(attrs)
        if doc = collection.find(_id: id).find_one_and_update({'$set' => attrs}, return_document: :after)
          # Clear out keys that are not returned during the reload from MongoDB
          (fields.keys + embedded_relations.keys - doc.keys).each { |key| send("#{key}=", nil) }
          @attributes = attributes
          apply_defaults
          self
        else
          raise Mongoid::Error::DocumentNotFound, "Document match #{_id.inspect} does not exist in #{collection.name} collection"
        end
      end

    end
  end
end

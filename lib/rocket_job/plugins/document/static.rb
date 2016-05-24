module RocketJob
  module Plugins
    # Extension for Document to implement static keys
    # Remove when new MongoMapper gem is released
    module Document
      module Static
        extend ActiveSupport::Concern

        module ClassMethods
          def embedded_keys
            @embedded_keys ||= embedded_associations.collect(&:as)
          end

          def embedded_key?(key)
            embedded_keys.include?(key.to_sym)
          end
        end

        private

        def load_from_database(attrs, with_cast = false)
          return super if !self.class.static_keys || !attrs.respond_to?(:each)

          attrs = attrs.select { |key, _| self.class.key?(key) || self.class.embedded_key?(key) }

          super(attrs, with_cast)
        end
      end
    end
  end
end

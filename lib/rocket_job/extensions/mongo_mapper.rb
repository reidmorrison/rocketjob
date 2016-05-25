# TODO Delete this file once PR has been accepted
#   https://github.com/mongomapper/mongomapper/pull/641
MongoMapper::Plugins::Keys::Static
module MongoMapper
  module Plugins
    module Keys
      module Static
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

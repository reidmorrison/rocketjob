require "active_support/concern"

module RocketJob
  module Batch
    module Callbacks
      extend ActiveSupport::Concern
      include ActiveSupport::Callbacks

      included do
        define_callbacks :slice

        def self.before_slice(*filters, &blk)
          set_callback(:slice, :before, *filters, &blk)
        end

        def self.after_slice(*filters, &blk)
          set_callback(:slice, :after, *filters, &blk)
        end

        def self.around_slice(*filters, &blk)
          set_callback(:slice, :around, *filters, &blk)
        end

        # before_batch and after_batch are called asynchronously.
        # around_batch is not supported.
        define_callbacks :before_batch
        define_callbacks :after_batch

        def self.before_batch(*filters, &blk)
          set_callback(:before_batch, :before, *filters, &blk)
        end

        def self.after_batch(*filters, &blk)
          set_callback(:after_batch, :after, *filters, &blk)
        end
      end
    end
  end
end

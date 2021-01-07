# TODO: Once the following PR has been merged and released in a gem, add a version check to exclude this patch.
#   https://github.com/mongodb/mongoid/pull/4944
require "mongoid/errors/mongoid_error"
module Mongoid
  module Errors
    # Default parent Mongoid error for all custom errors. This handles the base
    # key for the translations and provides the convenience method for
    # translating the messages.
    class MongoidError < StandardError
      def translate(key, options)
        ::I18n.translate("#{BASE_KEY}.#{key}", **options)
      end
    end
  end
end

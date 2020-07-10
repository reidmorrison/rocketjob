require "mongoid/fields/validators/macro"
require "semantic_logger"
module RocketJob
  module RemoveMongoidWarnings
    # Remove annoying warnings about Symbols type being deprecated.
    def validate_options(*params)
      SemanticLogger.silence(:error) { super(*params) }
    end
  end
end

::Mongoid::Fields::Validators::Macro.extend(RocketJob::RemoveMongoidWarnings)

require "active_support/concern"

module RocketJob
  module Batch
    # For holding multiple categorized Result's
    class Results < Array
    end
  end
end

require "active_support/concern"

module RocketJob
  module Batch
    # Structure to hold results that need to be written to different output collections
    Result = Struct.new(:category, :value)
  end
end

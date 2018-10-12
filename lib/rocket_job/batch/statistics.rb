require 'active_support/concern'

module RocketJob
  module Batch
    # Allow statistics to be gathered while a batch job is running
    module Statistics
      extend ActiveSupport::Concern

      class Stats
        attr_reader :stats, :in_memory

        # hash [Hash]
        #   Update an `in-memory` copy of the stats instead of gathering them inside `stats`.
        def initialize(hash = nil)
          @in_memory = hash
          @stats     = Hash.new(0) unless hash
        end

        def inc(hash)
          hash.each_pair { |key, increment| inc_key(key, increment) }
          self
        end

        def inc_key(key, increment = 1)
          return if increment == 0
          if in_memory
            # For tests and in-process execution
            inc_in_memory(key, increment)
          elsif key && key != ''
            stats["statistics.#{key}"] += increment
          end
          self
        end

        def empty?
          stats.nil? || stats.empty?
        end

        private

        # Navigates path and creates child hashes as needed at the end is reached
        def inc_in_memory(key, increment)
          paths = key.to_s.split('.')
          last  = paths.pop
          return unless last

          target = paths.inject(in_memory) {|target, key| target.key?(key) ? target[key] : target[key]  = Hash.new(0)}
          target[last] += increment
        end
      end

      included do
        field :statistics, type: Hash, default: -> { Hash.new(0) }

        around_slice :statistics_capture
      end

      # Increment a statistic
      def statistics_inc(key, increment = 1)
        return if key.nil? || key == ''
        # Being called within tests outside of a perform
        @slice_statistics ||= Stats.new(new_record? ? statistics : nil)
        key.is_a?(Hash) ? @slice_statistics.inc(key) : @slice_statistics.inc_key(key, increment)
      end

      private

      # Capture the number of successful and failed tradelines
      # as well as those with notices and alerts.
      def statistics_capture
        @slice_statistics = Stats.new(new_record? ? statistics : nil)
        yield
        collection.update_one({_id: id}, {'$inc' => @slice_statistics.stats}) unless @slice_statistics.empty?
      end
    end
  end
end

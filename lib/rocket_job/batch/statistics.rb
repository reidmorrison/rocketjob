require "active_support/concern"

module RocketJob
  module Batch
    # Allow statistics to be gathered while a batch job is running.
    #
    # Notes:
    # - Statistics for successfully processed records within a slice are saved.
    # - Statistics gathered during a perform that then results in an exception are discarded.
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
          return if increment.zero?

          if in_memory
            # For tests and in-process execution
            inc_in_memory(key, increment)
          elsif key && key != ""
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
          paths = key.to_s.split(".")
          last  = paths.pop
          return unless last

          last_target       = paths.inject(in_memory) do |target, sub_key|
            target.key?(sub_key) ? target[sub_key] : target[sub_key] = Hash.new(0)
          end
          last_target[last] += increment
        end
      end

      included do
        field :statistics, type: Hash, default: -> { Hash.new(0) }

        around_slice :rocket_job_statistics_capture
        after_perform :rocket_job_statistics_commit
      end

      # Increment a statistic
      def statistics_inc(key, increment = 1)
        return if key.nil? || key == ""

        (@rocket_job_perform_statistics ||= []) << (key.is_a?(Hash) ? key : [key, increment])
      end

      private

      def rocket_job_statistics_capture
        @rocket_job_perform_statistics = nil
        @rocket_job_slice_statistics   = nil
        yield
      ensure
        if @rocket_job_slice_statistics && !@rocket_job_slice_statistics.empty?
          collection.update_one({_id: id}, {"$inc" => @rocket_job_slice_statistics.stats})
        end
      end

      def rocket_job_slice_statistics
        @rocket_job_slice_statistics ||= Stats.new(new_record? ? statistics : nil)
      end

      # Apply stats gathered during the perform to the slice level stats
      def rocket_job_statistics_commit
        return unless @rocket_job_perform_statistics

        @rocket_job_perform_statistics.each do |key|
          key.is_a?(Hash) ? rocket_job_slice_statistics.inc(key) : rocket_job_slice_statistics.inc_key(*key)
        end

        @rocket_job_perform_statistics = nil
      end

      # Overrides RocketJob::Batch::Logger#rocket_job_batch_log_payload
      def rocket_job_batch_log_payload
        h              = {
          from:  aasm.from_state,
          to:    aasm.to_state,
          event: aasm.current_event
        }
        h[:statistics] = statistics.dup if statistics.present? && (completed? || failed?)
        h
      end
    end
  end
end

require "active_support/concern"
module RocketJob
  module Batch
    # Model attributes
    module Model
      extend ActiveSupport::Concern

      included do
        #
        # User definable attributes
        #
        # The following attributes are set when the job is created

        # The file name of the uploaded file, if any.
        # Set by #upload if a file name was supplied, but can also be set explicitly.
        # May or may not include the fully qualified path name.
        field :upload_file_name, type: String

        #
        # Values that jobs can also update during processing
        #

        # Number of records in this job
        # Note:
        #   A record_count of nil means it has not been set and workers will
        #   _not_ complete the job when processing slices.
        #   This allows workers to start processing slices while slices are still
        #   being uploaded
        field :record_count, type: Integer

        #
        # Read-only attributes
        #

        # Breaks the :running state up into multiple sub-states:
        #   :running -> :before -> :processing -> :after -> :complete
        field :sub_state, type: Mongoid::StringifiedSymbol
      end

      # Returns [Integer] percent of records completed so far
      # Returns 0 if the total record count has not yet been set
      def percent_complete
        return 100 if completed?
        return 0 unless record_count.to_i.positive?

        # Approximate number of input records
        input_records = input.count.to_f * input_category.slice_size
        if input_records > record_count
          # Sanity check in case slice_size is not being adhered to
          0
        else
          ((1.0 - (input_records.to_f / record_count)) * 100).to_i
        end
      end

      # Returns [Hash] status of this job
      def status(time_zone = "Eastern Time (US & Canada)")
        h = {}
        if queued?
          h["queued_slices"] = input.queued.count
        elsif running? || paused? || failed?
          h["active_slices"] = worker_count
          h["failed_slices"] = input.failed.count
          h["queued_slices"] = input.queued.count
          output_categories.each do |category|
            name_str                      = category.name == :main ? "" : "_#{category.name}"
            h["output_slices#{name_str}"] = output(category).count
          end
          # Very high level estimated time left
          if record_count && running? && record_count.positive?
            percent = percent_complete
            if percent >= 5
              secs                        = seconds.to_f
              h["est_remaining_duration"] = RocketJob.seconds_as_duration((((secs / percent) * 100) - secs))
            end
          end
        elsif completed?
          secs                  = seconds.to_f
          h["records_per_hour"] = ((record_count.to_f / secs) * 60 * 60).round if record_count&.positive? && (secs > 0.0)
        end
        h.merge!(super(time_zone))
        h.delete("result")
        # Worker name should be retrieved from the slices when processing
        h.delete("worker_name") if sub_state == :processing
        h
      end

      # Returns [Array<String>] names of workers currently working this job.
      def worker_names
        return [] unless running?

        case sub_state
        when :before, :after
          [worker_name]
        when :processing
          input.running.collect(&:worker_name)
        else
          []
        end
      end

      # Returns [Integer] the number of workers currently working on this job.
      def worker_count
        return 0 unless running?
        # Cache the number of workers for 1 second.
        return @worker_count if @worker_count_last && (@worker_count_last == Time.now.to_i)

        @worker_count      =
          case sub_state
          when :before, :after
            1
          when :processing
            input.running.count
          else
            0
          end
        @worker_count_last = Time.now.to_i
        @worker_count
      end
    end
  end
end

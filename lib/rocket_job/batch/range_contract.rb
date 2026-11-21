module RocketJob
  module Batch
    # The input contract of a job that uploads a range of integers, such as `job.upload(1..1_000_000)`, whose records
    # are each one range of ids, `[first_id, last_id]`, of up to `slice_size` ids, one per slice, see
    # RocketJob::Batch::IO#upload. `#perform` receives a record of this contract, read by position, rather than the Array.
    # It reads the row of each range as an upload writes it, and does not lay it out, so a job without a contract is
    # unchanged.
    #
    # Example:
    #   class ReprocessUsersJob < RocketJob::Job
    #     include RocketJob::Batch
    #
    #     input_contract RocketJob::Batch::RangeContract
    #
    #     def perform(range)
    #       User.where(id: range.to_range).find_each(&:reprocess!)
    #     end
    #   end
    #
    # A job can subclass it to add methods of its own to each range.
    class RangeContract < IOStreams::Contract
      field :first_id, :integer, required: true
      field :last_id, :integer, required: true

      # Returns [Range] the ids of this range, from the first to the last, also when the range was uploaded in
      # descending order, whose slices are processed from the highest ids, but whose ranges each still start with the
      # lowest id.
      def to_range
        first_id..last_id
      end
    end
  end
end

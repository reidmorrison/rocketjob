# frozen_string_literal: true

module RocketJob
  module Sliced
    # Holds the last slice that IOStreams writes to it, see `IOStreams::Slice::Target`, in memory, rather than storing it:
    # such as one range of ids, see Sliced::Input#range_slice, or the records that an input category writes in its
    # format, to ask the slice how IOStreams wrote them, see Category::Input#check_record_upload.
    class SliceHolder
      include IOStreams::Slice::Target

      # Returns [IOStreams::Slice] the last slice written, or nil when none was.
      attr_reader :slice

      def write_slice(slice)
        @slice = slice
      end
    end
  end
end

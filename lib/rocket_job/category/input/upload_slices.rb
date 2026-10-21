module RocketJob
  module Category
    class Input
      # The slices of the rows of a file that an upload reads, see #each_slice and #each_written_slice, which calls
      # `on_first` once before the first is yielded: with a copy of the header row of the file, an Array of its columns
      # as they are in the file, or for a file without one, such as JSON or fixed width, with its first row, which is
      # then not uploaded. Each slice that has rows is yielded.
      class UploadSlices
        def initialize(on_first, &on_slice)
          @on_first = on_first
          @on_slice = on_slice
        end

        # Yields the supplied slice, see IOStreams::Slice, after calling `on_first` with its header row, or its first
        # row, the first time.
        def <<(slice)
          first(slice.header ? copy(slice.header) : slice.shift) if @on_first
          @on_slice.call(slice) unless slice.empty?
          self
        end

        # Calls `on_first` with the supplied header row of a file without rows after it, when no slice called it.
        def finish(header)
          first(copy(header)) if @on_first && header
        end

        private

        def first(row)
          on_first  = @on_first
          @on_first = nil
          on_first.call(row)
        end

        # Returns [Array<String>] a copy of the supplied header row, which every slice of the file shares, so that
        # `on_first` can change it.
        def copy(header)
          header.map { |column| column&.dup }
        end
      end
    end
  end
end

module RocketJob
  module Sliced
    module Writer
      # Internal class for uploading records into input slices
      class Input
        attr_reader :record_count

        # Batch collection of lines into slices.
        #
        # Parameters
        #   on_first: [Proc]
        #     Block to call on the first line only, instead of storing in the slice.
        #     Useful for extracting the header row
        #     Default: nil
        #
        #   slice_size: [Integer]
        #     Override the slice size when uploading for example ranges, where slice is the size
        #     of the range itself.
        #
        #   slice_batch_size: [Integer]
        #     The number of slices to batch up and to bulk load.
        #     For smaller slices this significantly improves upload performance.
        #     Note: If `slice_batch_size` is too high, it can exceed the maximum BSON block size.
        def self.collect(data_store, **args)
          writer = new(data_store, **args)
          yield(writer)
          writer.record_count
        ensure
          writer&.flush
        end

        def initialize(data_store, on_first: nil, slice_size: nil, slice_batch_size: 20)
          @on_first         = on_first
          @record_count     = 0
          @data_store       = data_store
          @slice_size       = slice_size || @data_store.slice_size
          @slice_batch_size = slice_batch_size
          @batch            = []
          @batch_count      = 0
          new_slice
        end

        def <<(line)
          if @on_first
            @on_first.call(line)
            @on_first = nil
            return self
          end
          @slice << line
          @record_count += 1
          if @slice.size >= @slice_size
            save_slice
            new_slice
          end
          self
        end

        def flush
          if @slice_batch_size
            @batch << @slice if @slice.size.positive?
            @data_store.insert_many(@batch)
            @batch       = []
            @batch_count = 0
          elsif @slice.size.positive?
            @data_store.insert(@slice)
          end
        end

        def new_slice
          @slice = @data_store.new(first_record_number: @record_count + 1)
        end

        def save_slice
          return flush unless @slice_batch_size

          @batch_count += 1
          return flush if @batch_count >= @slice_batch_size

          @batch << @slice
        end
      end
    end
  end
end

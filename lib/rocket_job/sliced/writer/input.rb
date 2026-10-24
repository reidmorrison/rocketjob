module RocketJob
  module Sliced
    module Writer
      # Internal class for uploading records into input slices.
      #
      # It is also a store of the slices of the rows of a file, see `IOStreams::Slice::Target`, so that IOStreams writes
      # the lines of a file to it in slices of `slice_size` rows, see #write_slice and
      # Category::Input#write_slices.
      class Input
        include IOStreams::Slice::Target

        attr_reader :record_count

        # Returns [Integer] the number of records of each slice, which IOStreams writes the slices of a file in, see
        # `IOStreams::Slice::Target#slice_size`.
        attr_reader :slice_size

        # Batch collection of lines into slices.
        #
        # Parameters
        #   slice_size: [Integer]
        #     Override the slice size when uploading for example ranges, where slice is the size
        #     of the range itself.
        #
        #   slice_batch_size: [Integer]
        #     The number of slices to batch up and to bulk load.
        #     For smaller slices this significantly improves upload performance.
        #     Note: If `slice_batch_size` is too high, it can exceed the maximum BSON block size.
        #
        #   upload_id: [String]
        #     The id of this upload, which each slice holds, see Slice#upload_id.
        #     Default: nil
        def self.collect(data_store, **args)
          writer = new(data_store, **args)
          yield(writer)
          writer.record_count
        ensure
          writer&.flush
        end

        def initialize(data_store, slice_size: nil, slice_batch_size: nil, upload_id: nil)
          @upload_id        = upload_id
          @record_count     = 0
          @data_store       = data_store
          @slice_size       = slice_size || @data_store.slice_size
          @slice_batch_size = slice_batch_size || 20
          @batch            = []
          @batch_count      = 0
          new_slice
        end

        def <<(line)
          @slice << line
          @record_count += 1
          if @slice.size >= @slice_size
            save_slice
            new_slice
          end
          self
        end

        # Stores the supplied rows of a file, see IOStreams::Slice, as a slice of their own, numbered after the records
        # already written, so that they keep the header row and format that they carry. They are neither split nor
        # joined with other records, since IOStreams read them in slices of `slice_size` rows.
        def write_slice(rows)
          return self if rows.empty?

          unless @slice.records.empty?
            save_slice
            new_slice
          end
          @slice.records = rows
          @record_count += rows.size
          save_slice
          new_slice
          self
        end

        def flush
          if @slice_batch_size
            @batch << @slice if @slice.size.positive?
            save_slices(@batch) { @data_store.insert_many(@batch) }
            @batch       = []
            @batch_count = 0
          elsif @slice.size.positive?
            save_slices([@slice]) { @data_store.insert(@slice) }
          end
        end

        def new_slice
          attributes             = {first_record_number: @record_count + 1}
          attributes[:upload_id] = @upload_id if @upload_id
          @slice                 = @data_store.new(attributes)
        end

        def save_slice
          return flush unless @slice_batch_size

          @batch_count += 1
          return flush if @batch_count >= @slice_batch_size

          @batch << @slice
        end

        private

        # Saves the supplied slices with the block. When a record holds text that MongoDB cannot store, since it is
        # binary or not valid UTF-8, raises BSON's error with the number of the first such record, which its message
        # does not include, as the job numbers it, see Slice#current_record_number.
        #
        # Only the records written one at a time, see #<<, can hold such text: IOStreams writes the rows of a file as
        # UTF-8 text, see #write_slice, and raises for a character that is not valid with the line of the file it is on.
        def save_slices(slices)
          yield
        rescue EncodingError => e
          number = first_unstorable_record_number(slices)
          raise(e) unless number

          raise(e.exception("Cannot upload record #{number}, since MongoDB only stores UTF-8 text: #{e.message}"))
        end

        # Returns [Integer] the number of the first record in the supplied slices that BSON cannot store, or nil.
        def first_unstorable_record_number(slices)
          slices.each do |slice|
            slice.records.each_with_index do |record, index|
              {"r" => record}.to_bson
            rescue EncodingError
              return slice.first_record_number + index
            end
          end
          nil
        end
      end
    end
  end
end

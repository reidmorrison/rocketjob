module RocketJob
  module Sliced
    module Writer
      # Internal class for uploading records into input slices
      class Input
        attr_reader :record_count

        # Batch collection of lines into slices.
        #
        # Parameters
        #   on_first_line: [Proc]
        #     Block to call on the first line only, instead of storing in the slice.
        #     Useful for extracting the header row
        #     Default: nil
        def self.collect(input, **args, &block)
          writer = new(input, **args)
          block.call(writer)
          writer.record_count
        rescue Exception => exc
          # Drop input collection when upload fails
          input.drop
          raise exc
        ensure
          writer&.close
        end

        def initialize(input, on_first_line: nil)
          @on_first_line = on_first_line
          @batch_count   = 0
          @record_count  = 0
          @input         = input
          @record_number = 1
          @slice         = @input.new(first_record_number: @record_number)
        end

        def <<(line)
          @record_number += 1
          if @on_first_line
            @on_first_line.call(line)
            @on_first_line = nil
            return self
          end
          @slice << line
          @batch_count   += 1
          @record_count  += 1
          if @batch_count >= @input.slice_size
            @input.insert(@slice)
            @batch_count = 0
            @slice       = @input.new(first_record_number: @record_number)
          end
          self
        end

        def close
          @input.insert(@slice) if @slice.size.positive?
        end
      end
    end
  end
end

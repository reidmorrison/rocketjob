module RocketJob
  module Sliced
    module Writer
      # Internal class for uploading records into input slices
      class Input
        attr_reader :record_count

        def self.collect(input, &block)
          writer = new(input)
          block.call(writer)
          writer.record_count
        rescue Exception => exc
          # Drop input collection when upload fails
          input.drop
          raise exc
        ensure
          writer&.close
        end

        def initialize(input)
          @batch_count   = 0
          @record_count  = 0
          @input         = input
          @record_number = 1
          @slice         = @input.new(first_record_number: @record_number)
        end

        def <<(record)
          @slice << record
          @batch_count   += 1
          @record_count  += 1
          @record_number += 1
          if @batch_count >= @input.slice_size
            @input.insert(@slice)
            @batch_count = 0
            @slice       = @input.new(first_record_number: @record_number)
          end
        end

        def close
          @input.insert(@slice) if @slice.size.positive?
        end
      end
    end
  end
end

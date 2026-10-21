module RocketJob
  module Category
    class Input
      # The writer that the block of an upload into a category with a schema writes the lines of a file to, see
      # #each_written_slice, which reads them as IOStreams reads the lines of a file in slices, see
      # `IOStreams::Slice::Reader`, with one tabular, so that the header row is read and matched to the fields once: the
      # tabular reads the header row from the first lines, when the file has one, and each line after it is a row,
      # which it also parses when `validate` is true, so that a row that is not valid raises when it is written. Each
      # slice of up to `size` rows, which holds the header row, is added to the supplied slices, see UploadSlices.
      class WrittenLines
        def initialize(tabular, slices, size:, validate:)
          @tabular  = tabular
          @slices   = slices
          @size     = size
          @validate = validate
          @slice    = nil
        end

        # Yields this writer to the supplied block of an upload, then adds the rows written since the last slice, and
        # the header row, see UploadSlices#finish. The lines written before the block breaks out are added too, as
        # without a schema, see Sliced::Writer::Input, but not when it raises, since the upload is then removed.
        def write(block)
          block.call(self)
        rescue Exception
          failed = true
          raise
        ensure
          unless failed
            flush
            @slices.finish(@tabular.header_row)
          end
        end

        # Adds the supplied line, and the slice of the rows added, once it has `size` of them.
        #
        # Raises ArgumentError for a record that is not a line, such as a Hash.
        def <<(line)
          unless line.is_a?(String)
            raise(ArgumentError, "Write each line of a file to the upload of an input category with a schema, not a " \
                                 "#{line.class.name}")
          end

          @tabular.read_line(line) do |row|
            @tabular.record_parse(row) if @validate
            (@slice ||= IOStreams::Slice.new(header: @tabular.header_row, format: @tabular.format)) << row
            flush if @slice.size >= @size
          end
          self
        end

        private

        # Adds the slice of the rows added since the last one, when there are any.
        def flush
          return unless @slice

          slice  = @slice
          @slice = nil
          @slices << slice
        end
      end
    end
  end
end

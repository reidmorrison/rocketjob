module RocketJob
  module Category
    # Internal: a writer whose first record decides the mode that IOStreams writes every record in, see
    # Input#write_slices and Output#output_writer: a String as a line (:line), a Hash as a record (:hash), and an Array
    # as a row (:array), unless the mode is supplied. IOStreams takes a writer in one mode within a block, so it is
    # opened on the first record in a Fiber, which each later record resumes, and which #finish closes. What IOStreams
    # raises for a record, such as one of another kind than the first, is raised when it is written, so that the error
    # names it, and the writer stays open for the records after it.
    class FirstRecordWriter
      # Marks the end of the records, see #finish.
      DONE = Object.new.freeze

      # Yields a writer to the supplied block of an upload, which closes it once the block returns, also when it breaks
      # out, which keeps the records written before it, as IOStreams does, and discards them when the block raises.
      def self.write(upload_block, &)
        writer  = new(&)
        aborted = false
        begin
          upload_block.call(writer)
        rescue Exception => e
          aborted = true
          writer.abort(e)
          raise
        ensure
          writer.finish unless aborted
        end
      end

      # Parameters
      #   mode: [Symbol]
      #     The mode to write every record in, rather than the one that the first record gives.
      #   open: [Proc]
      #     Called with the mode, and the block that writes the records to the IOStreams writer of that mode.
      def initialize(mode: nil, &open)
        @mode = mode
        @open = open
      end

      # Returns [true|false] whether a record was written, which opened the IOStreams writer.
      def started?
        !@fiber.nil?
      end

      # Writes the supplied record. Returns self, so that calls can be chained.
      #
      # Raises what IOStreams raised for the record, which leaves the records written before it, and the writer open for
      # those after it, so that the caller decides whether to go on, or to keep what was written.
      def <<(record)
        error = @fiber ? @fiber.resume(record) : start(record)
        raise(error) if error

        self
      end

      # Closes the IOStreams writer, once every record is written.
      def finish
        @fiber.resume(DONE) if @fiber&.alive?
        nil
      end

      # Raises the supplied exception within the IOStreams writer, which discards what it has not written.
      def abort(exception)
        @fiber.raise(exception) if @fiber&.alive?
      rescue Exception # rubocop:disable Lint/SuppressedException -- the caller raises its own exception
      end

      private

      def start(record)
        mode   = @mode || mode_of(record)
        # The first record is not passed to #resume, since JRuby spreads an Array passed to the first #resume over the
        # parameters of the block, which would give it only the first value of a row.
        @fiber = Fiber.new do
          @open.call(mode) do |io|
            current = record
            until current.equal?(DONE)
              error = nil
              begin
                io << current
              rescue Exception => e
                error = e
              end
              current = Fiber.yield(error)
            end
          end
        end
        @fiber.resume
      end

      def mode_of(record)
        return :hash if record.is_a?(Hash)

        record.is_a?(Array) ? :array : :line
      end
    end
  end
end

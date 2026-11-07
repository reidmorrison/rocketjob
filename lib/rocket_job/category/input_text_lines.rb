module RocketJob
  module Category
    # How an input category reads the lines of a text file that it uploads, see Input#each_record.
    module InputTextLines
      private

      # Yields each line read from the supplied path, see Input#each_record. In a format the path reads the text, see
      # Input#upload_path. Without one, IOStreams reads a line as binary, since no encoding is set on the path, which
      # MongoDB cannot store when it holds a letter that is not ASCII, such as `José`: so the line is taken as UTF-8, without
      # the byte order mark that a UTF-8 file can start with, which is not part of its text. A line read in an encoding
      # set on the path, such as ISO-8859-1, is yielded as it is, and stored as UTF-8.
      #
      # Text that is not valid UTF-8 raises IOStreams::Errors::InvalidEncoding, naming its line, and uploads nothing,
      # as with a schema.
      def each_line(path, **args, &)
        return path.each(:line, **args, &) if tabular?

        path.reader(:line, **args) do |lines|
          line_number = 1
          lines.each do |line|
            if line.encoding == Encoding::BINARY
              line.force_encoding(Encoding::UTF_8)
              line.delete_prefix!("﻿") if line_number == 1
            end
            if line.encoding == Encoding::UTF_8 && !line.valid_encoding?
              raise(IOStreams::Utils.invalid_utf8(line, line_number: line_number))
            end

            yield(line)
            # A line can hold a line break within quotes, such as of a CSV file, so the next one starts after it.
            line_number = lines.line_number + 1
          end
        end
      end
    end
  end
end

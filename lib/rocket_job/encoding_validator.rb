require "active_model"

module RocketJob
  # Validates that each attribute, when it is set, is the name of one encoding that Ruby knows, such as
  # "Windows-1252", for the text in a file, see RocketJob::Category::Base#encoding and
  # RocketJob::Jobs::CopyFileJob#source_encoding.
  #
  # A conversion, such as "Windows-1252:UTF-8", is not valid, since the text is always converted to and from the
  # UTF-8 that MongoDB stores. Nor is a name that is not the encoding of the text in a file:
  # * "locale", "external", "filesystem" and "internal", the default encodings of the process, which can differ
  #   between the servers that read the file.
  # * "BINARY", or "ASCII-8BIT", which is bytes, not text.
  # * "UTF-16" and "UTF-32", which write a byte order mark in front of every piece of text that they convert, such
  #   as each slice of output, rather than once at the start of the file. Name the byte order, such as "UTF-16LE".
  # * An encoding that Ruby cannot convert to and from UTF-8, such as "UTF-7".
  #
  # Example:
  #   validates_with RocketJob::EncodingValidator, attributes: [:encoding]
  class EncodingValidator < ActiveModel::EachValidator
    # The names that Encoding.find accepts for the default encodings of the process.
    PROCESS_ENCODING_NAMES = %w[locale external filesystem internal].freeze

    # The encodings whose conversion writes a byte order mark.
    BYTE_ORDER_MARK_ENCODINGS = [Encoding::UTF_16, Encoding::UTF_32].freeze

    def validate_each(record, attribute, value)
      return if value.blank?

      if value.include?(":")
        return record.errors.add(attribute, "must name one encoding, such as Windows-1252, not a conversion")
      end

      message = text_encoding_error(value)
      record.errors.add(attribute, message) if message
    end

    private

    # Returns [String] why the supplied name is not the encoding of the text in a file, or nil when it is.
    def text_encoding_error(name)
      if PROCESS_ENCODING_NAMES.include?(name.downcase)
        return "#{name.inspect} is the default encoding of the process, which can differ between servers, " \
               "so name the encoding, such as UTF-8"
      end

      encoding = Encoding.find(name)
      return "#{name.inspect} is bytes, not the encoding of text" if encoding == Encoding::BINARY

      if BYTE_ORDER_MARK_ENCODINGS.include?(encoding)
        return "#{name.inspect} writes a byte order mark in front of each piece of text, " \
               "so name its byte order, such as #{encoding.name}LE"
      end

      Encoding::Converter.new(encoding, Encoding::UTF_8)
      Encoding::Converter.new(Encoding::UTF_8, encoding)
      nil
    rescue Encoding::ConverterNotFoundError
      "#{name.inspect} is an encoding that Ruby cannot convert to and from UTF-8"
    rescue ArgumentError
      "#{name.inspect} is not an encoding that Ruby knows, such as Windows-1252"
    end
  end
end

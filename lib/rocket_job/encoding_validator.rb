require "active_model"

module RocketJob
  # Validates that each attribute, when it is set, is the name of one encoding that Ruby knows, such as
  # "Windows-1252", for the text in a file, see RocketJob::Category::Base#encoding and
  # RocketJob::Jobs::CopyFileJob#source_encoding.
  #
  # A conversion, such as "Windows-1252:UTF-8", is not valid, since the text is always converted to and from the
  # UTF-8 that MongoDB stores.
  #
  # Example:
  #   validates_with RocketJob::EncodingValidator, attributes: [:encoding]
  class EncodingValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      return if value.blank?

      if value.include?(":")
        return record.errors.add(attribute, "must name one encoding, such as Windows-1252, not a conversion")
      end

      Encoding.find(value)
    rescue ArgumentError
      record.errors.add(attribute, "#{value.inspect} is not an encoding that Ruby knows, such as Windows-1252")
    end
  end
end

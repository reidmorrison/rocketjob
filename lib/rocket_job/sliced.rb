module RocketJob
  module Sliced
    autoload :BZip2OutputSlice, "rocket_job/sliced/bzip2_output_slice"
    autoload :CompressedSlice, "rocket_job/sliced/compressed_slice"
    autoload :EncryptedSlice, "rocket_job/sliced/encrypted_slice"
    autoload :Input, "rocket_job/sliced/input"
    autoload :Output, "rocket_job/sliced/output"
    autoload :Slice, "rocket_job/sliced/slice"
    autoload :Slices, "rocket_job/sliced/slices"
    autoload :Store, "rocket_job/sliced/store"

    module Writer
      autoload :Input, "rocket_job/sliced/writer/input"
      autoload :Output, "rocket_job/sliced/writer/output"
    end

    # Returns [RocketJob::Sliced::Slices] for the relevant type and category.
    #
    # Supports compress and encrypt with [true|false|Hash] values.
    # When [Hash] they must specify whether the apply to the input or output collection types.
    #
    # Example, compress both input and output collections:
    #   class MyJob < RocketJob::Job
    #     include RocketJob::Batch
    #     self.compress = true
    #   end
    #
    # Example, compress just the output collections:
    #   class MyJob < RocketJob::Job
    #     include RocketJob::Batch
    #     self.compress = {output: true}
    #   end
    #
    # To use the specialized BZip output compressor, and the regular compressor for the input collections:
    #   class MyJob < RocketJob::Job
    #     include RocketJob::Batch
    #     self.compress = {output: :bzip2, input: true}
    #   end
    def self.factory(type, category, job)
      raise(ArgumentError, "Unknown type: #{type.inspect}") unless %i[input output].include?(type)

      collection_name = "rocket_job.#{type}s.#{job.id}"
      collection_name << ".#{category}" unless category == :main

      args               = {collection_name: collection_name, slice_size: job.slice_size}
      klass              = slice_class(type, job)
      args[:slice_class] = klass if klass

      if type == :input
        RocketJob::Sliced::Input.new(**args)
      else
        RocketJob::Sliced::Output.new(**args)
      end
    end

    private

    # Parses the encrypt and compress options to determine which slice serializer to use.
    # `encrypt` takes priority over any `compress` option.
    def self.slice_class(type, job)
      encrypt  = extract_value(type, job.encrypt)
      compress = extract_value(type, job.compress)

      if encrypt
        case encrypt
        when true
          EncryptedSlice
        else
          raise(ArgumentError, "Unknown job `encrypt` value: #{compress}") unless compress.is_a?(Slices)
          # Returns the supplied class to use for encryption.
          encrypt
        end
      elsif compress
        case compress
        when true
          CompressedSlice
        when :bzip2
          BZip2OutputSlice
        else
          raise(ArgumentError, "Unknown job `compress` value: #{compress}") unless compress.is_a?(Slices)
          # Returns the supplied class to use for compression.
          compress
        end
      end
    end

    def self.extract_value(type, value)
      value.is_a?(Hash) ? value[type] : value
    end
  end
end

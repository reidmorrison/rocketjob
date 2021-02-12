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

    # Returns [RocketJob::Sliced::Slices] for the relevant direction and category.
    def self.factory(direction, category, job)
      collection_name = "rocket_job.#{direction}s.#{job.id}"
      collection_name << ".#{category.name}" unless category.name == :main

      args = {
        collection_name: collection_name,
        slice_size:      job.slice_size,
        slice_class:     category.serializer_class(default_encrypt: job.encrypt, default_compress: job.compress)
      }

      case direction
      when :input
        RocketJob::Sliced::Input.new(**args)
      when :output
        RocketJob::Sliced::Output.new(**args)
      else
        raise(ArgumentError, "Unknown direction: #{direction.inspect}")
      end
    end
  end
end

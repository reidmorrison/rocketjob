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

      case direction
      when :input
        RocketJob::Sliced::Input.new(
          collection_name: collection_name,
          slice_class:     category.serializer_class,
          slice_size:      category.slice_size
        )
      when :output
        RocketJob::Sliced::Output.new(collection_name: collection_name, slice_class: category.serializer_class)
      else
        raise(ArgumentError, "Unknown direction: #{direction.inspect}")
      end
    end
  end
end

require 'active_support/concern'

module RocketJob
  module Batch
    # IO methods for sliced jobs
    module IO
      extend ActiveSupport::Concern

      # Returns [RocketJob::Sliced::Input] input collection for holding input slices
      #
      # Parameters:
      #   category [Symbol]
      #     The name of the category to access or upload data into
      #     Default: None ( Uses the single default input collection for this job )
      #     Validates: This value must be one of those listed in #input_categories
      def input(category = :main)
        raise "Category #{category.inspect}, must be registered in input_categories: #{input_categories.inspect}" unless input_categories.include?(category) || (category == :main)

        collection_name = "rocket_job.inputs.#{id}"
        collection_name << ".#{category}" unless category == :main

        (@inputs ||= {})[category] ||= RocketJob::Sliced::Input.new(slice_arguments(collection_name))
      end

      # Returns [RocketJob::Sliced::Output] output collection for holding output slices
      # Returns nil if no output is being collected
      #
      # Parameters:
      #   category [Symbol]
      #     The name of the category to access or download data from
      #     Default: None ( Uses the single default output collection for this job )
      #     Validates: This value must be one of those listed in #output_categories
      def output(category = :main)
        raise "Category #{category.inspect}, must be registered in output_categories: #{output_categories.inspect}" unless output_categories.include?(category) || (category == :main)

        collection_name = "rocket_job.outputs.#{id}"
        collection_name << ".#{category}" unless category == :main

        (@outputs ||= {})[category] ||= RocketJob::Sliced::Output.new(slice_arguments(collection_name))
      end

      # Upload the supplied file_name or stream
      #
      # Updates the record_count after adding the records
      #
      # Options
      #     :file_name [String]
      #       When file_name_or_io is an IO, the original base file name if any.
      #       Default: nil
      #
      # See RocketJob::Sliced::Input#upload for remaining options
      #
      # Returns [Integer] the number of records uploaded
      #
      # Note:
      # * Not thread-safe. Only call from one thread at a time
      def upload(file_name_or_io = nil, file_name: nil, category: :main, **args, &block)
        if file_name
          self.upload_file_name = file_name
        elsif file_name_or_io.is_a?(String)
          self.upload_file_name = file_name_or_io
        end
        count             = input(category).upload(file_name_or_io, file_name: file_name, **args, &block)
        self.record_count = (record_count || 0) + count
        count
      end

      # Upload the supplied slices for processing by workers
      #
      # Updates the record_count after adding the records
      #
      # Returns [Integer] the number of records uploaded
      #
      # Parameters
      #   `slice` [ Array<Hash | Array | String | Integer | Float | Symbol | Regexp | Time> ]
      #     All elements in `array` must be serializable to BSON
      #     For example the following types are not supported: Date
      #
      # Note:
      #   The caller should honor `:slice_size`, the entire slice is loaded as-is.
      #
      # Note:
      #   Not thread-safe. Only call from one thread at a time
      def upload_slice(slice)
        input.insert(slice)
        count             = slice.size
        self.record_count = (record_count || 0) + count
        count
      end

      # Download the output data into the supplied file_name or stream
      #
      # Parameters
      #   file_name_or_io [String|IO]
      #     The file_name of the file to write to, or an IO Stream that implements #write.
      #
      #   options:
      #     category [Symbol]
      #       The category of output to download
      #       Default: :main
      #
      # See RocketJob::Sliced::Output#download for remaining options
      #
      # Returns [Integer] the number of records downloaded
      def download(file_name_or_io = nil, category: :main, **args, &block)
        raise "Cannot download incomplete job: #{id}. Currently in state: #{state}-#{sub_state}" if rocket_job_processing?

        output(category).download(file_name_or_io, **args, &block)
      end

      # Writes the supplied result, Result or CompositeResult to the relevant collections.
      #
      # If a block is supplied, the block is supplied with a writer that should be used to
      # accumulate the results.
      #
      # Examples
      #
      # job.write_output('hello world')
      #
      # job.write_output do |writer|
      #   writer << 'hello world'
      # end
      #
      # job.write_output do |writer|
      #   result = RocketJob::Sliced::CompositeResult
      #   result << RocketJob::Sliced::Result.new(:main, 'hello world')
      #   result << RocketJob::Sliced::Result.new(:errors, 'errors')
      #   writer << result
      # end
      #
      # result = RocketJob::Sliced::CompositeResult
      # result << RocketJob::Sliced::Result.new(:main, 'hello world')
      # result << RocketJob::Sliced::Result.new(:errors, 'errors')
      # job.write_output(result)
      def write_output(result = nil, input_slice = nil, &block)
        if block
          RocketJob::Sliced::Writer::Output.collect(self, input_slice, &block)
        else
          raise(ArgumentError, 'result parameter is required when no block is supplied') unless result
          RocketJob::Sliced::Writer::Output.collect(self, input_slice) { |writer| writer << result }
        end
      end

      private

      def slice_arguments(collection_name)
        {
          collection_name: collection_name,
          slice_size:      slice_size
        }
      end
    end
  end
end

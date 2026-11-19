module RocketJob
  module Sliced
    module Writer
      class Null
        attr_reader :job, :categorized_records
        attr_accessor :input_slice, :append

        def initialize(job, input_slice: nil, append: false)
          @job                 = job
          @input_slice         = input_slice
          @categorized_records = {}
          @append              = append
        end

        def <<(_)
          # noop
        end

        def close
          # noop
        end
      end

      # Internal class for writing categorized results into output slices
      class Output < Null
        # Collect output results and write to output collections
        # iff job is collecting output
        # Notes:
        #   Partial slices are saved when an exception is raised inside the block
        def self.collect(job, **args)
          writer = job.output_categories.present? ? new(job, **args) : Null.new(job, **args)
          yield(writer)
        ensure
          writer&.close
        end

        # Writes the supplied result, RocketJob::Batch::Result or RocketJob::Batch::Results
        # to the relevant collections
        #
        # The results of one record are written whole: when one of them cannot be written, those written before it are
        # dropped, since the record runs again when its slice is retried.
        def <<(result)
          return extract_categorized_result(result) unless result.is_a?(RocketJob::Batch::Results)

          sizes = categorized_records.transform_values(&:size)
          begin
            result.each { |single| extract_categorized_result(single) }
          rescue Exception
            categorized_records.each_pair { |name, writer| writer.keep(sizes.fetch(name, 0)) }
            raise
          end
        end

        # Write categorized results to their relevant collections
        # Stores the records that each output category wrote, see RocketJob::Category::Output#output_writer, in its
        # output slice.
        def close
          categorized_records.each_pair do |name, writer|
            records    = writer.records
            collection = job.output(name)
            append ? collection.append(records, input_slice) : collection.insert(records, input_slice)
          end
        end

        private

        # Writes the categorized result from one result with the writer of its output category, see
        # RocketJob::Category::Output#output_writer, unless it is nil, which is only kept when the category keeps nils,
        # so that a result that cannot be written raises for the record that returned it.
        def extract_categorized_result(result)
          named_category = :main
          value          = result
          if result.is_a?(RocketJob::Batch::Result)
            named_category = result.category
            value          = result.value
          end
          category = output_category(named_category)
          return if value.nil? && !category.nils

          (categorized_records[named_category] ||= output_writer(named_category, category)) << value
        end

        # Returns [#<<] the writer of the results of the supplied output category, which appends to the records of the
        # output slice that an earlier attempt wrote, when there is one, see RocketJob::Category::Output#output_writer.
        def output_writer(name, category)
          existing = job.output(name).where(id: input_slice.id).first if append && input_slice
          category.output_writer(append_to: existing&.records)
        end

        # Returns [RocketJob::Category::Output] the named output category of the job, looked up once per slice.
        def output_category(name)
          (@output_categories ||= {})[name] ||= job.output_category(name)
        end
      end
    end
  end
end

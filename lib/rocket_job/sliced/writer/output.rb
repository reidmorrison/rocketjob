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
        def <<(result)
          if result.is_a?(RocketJob::Batch::Results)
            result.each { |single| extract_categorized_result(single) }
          else
            extract_categorized_result(result)
          end
        end

        # Write categorized results to their relevant collections
        # The output category writes the results of each category as the records of its output slice, see
        # RocketJob::Category::Output#output_records.
        def close
          categorized_records.each_pair do |name, results|
            records    = output_category(name).output_records(results)
            collection = job.output(name)
            append ? collection.append(records, input_slice) : collection.insert(records, input_slice)
          end
        end

        private

        # Keeps the categorized result from one result, unless it is nil, which is only kept when the category keeps
        # nils, for its output category to write when the slice is closed, see #close.
        def extract_categorized_result(result)
          named_category = :main
          value          = result
          if result.is_a?(RocketJob::Batch::Result)
            named_category = result.category
            value          = result.value
          end
          return if value.nil? && !output_category(named_category).nils

          (categorized_records[named_category] ||= []) << value
        end

        # Returns [RocketJob::Category::Output] the named output category of the job, looked up once per slice.
        def output_category(name)
          (@output_categories ||= {})[name] ||= job.output_category(name)
        end
      end
    end
  end
end

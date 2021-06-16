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
        def close
          categorized_records.each_pair do |category, results|
            collection = job.output(category)
            append ? collection.append(results, input_slice) : collection.insert(results, input_slice)
          end
        end

        private

        # Stores the categorized result from one result
        def extract_categorized_result(result)
          named_category = :main
          value          = result
          if result.is_a?(RocketJob::Batch::Result)
            named_category = result.category
            value          = result.value
          end
          (categorized_records[named_category] ||= []) << value unless value.nil? && !job.output_category(named_category).nils
        end
      end
    end
  end
end

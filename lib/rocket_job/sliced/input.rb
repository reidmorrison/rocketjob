module RocketJob
  module Sliced
    class Input < Slices
      def upload(**args, &)
        # Create indexes before uploading
        create_indexes
        Writer::Input.collect(self, **args, &)
      rescue Exception => e
        drop
        raise(e)
      end

      def upload_mongo_query(criteria, columns: [], slice_batch_size: nil, &block)
        options = criteria.options

        # Without a block extract the fields from the supplied criteria
        if block
          # Criteria is returning old school :fields instead of :projections
          options[:projection] = options.delete(:fields) if options.key?(:fields)
        else
          columns = columns.blank? ? ["_id"] : columns.collect(&:to_s)
          fields  = options.delete(:fields) || {}
          columns.each { |col| fields[col] = 1 }
          options[:projection] = fields

          block =
            if columns.size == 1
              column = columns.first
              ->(document) { document[column] }
            else
              ->(document) { columns.collect { |c| document[c] } }
            end
        end

        upload(slice_batch_size: slice_batch_size) do |records|
          # Drop down to the mongo driver level to avoid constructing a Model for each document returned
          criteria.klass.collection.find(criteria.selector, options).each do |document|
            records << block.call(document)
          end
        end
      end

      def upload_arel(arel, columns: nil, slice_batch_size: nil, &block)
        unless block
          columns = columns.blank? ? [:id] : columns.collect(&:to_sym)

          block =
            if columns.size == 1
              column = columns.first
              ->(model) { model.public_send(column) }
            else
              ->(model) { columns.collect { |c| model.public_send(c) } }
            end
          # find_each requires the :id column in the query
          selection = columns.include?(:id) ? columns : columns + [:id]
          arel      = arel.select(selection)
        end

        upload(slice_batch_size: slice_batch_size) { |records| arel.find_each { |model| records << block.call(model) } }
      end

      def upload_integer_range(start_id, last_id, slice_batch_size: 1_000)
        # Each "record" is actually a range of Integers which makes up each slice
        upload(slice_size: 1, slice_batch_size: slice_batch_size) do |records|
          while start_id <= last_id
            end_id = start_id + slice_size - 1
            end_id = last_id if end_id > last_id
            records << [start_id, end_id]
            start_id += slice_size
          end
        end
      end

      def upload_integer_range_in_reverse_order(start_id, last_id, slice_batch_size: 1_000)
        # Each "record" is actually a range of Integers which makes up each slice
        upload(slice_size: 1, slice_batch_size: slice_batch_size) do |records|
          end_id = last_id
          while end_id >= start_id
            first_id = end_id - slice_size + 1
            first_id = start_id if first_id.negative? || (first_id < start_id)
            records << [first_id, end_id]
            end_id -= slice_size
          end
        end
      end

      # Iterate over each failed record, if any
      # Since each slice can only contain 1 failed record, only the failed
      # record is returned along with the slice containing the exception
      # details
      #
      # Example:
      #   job.each_failed_record do |record, slice|
      #     ap slice
      #   end
      #
      def each_failed_record
        failed.each do |slice|
          record = slice.failed_record
          yield(record, slice) unless record.nil?
        end
      end

      # Requeue all failed slices
      def requeue_failed
        failed.update_all(
          "$unset" => {worker_name: nil, started_at: nil},
          "$set"   => {state: "queued"}
        )
      end

      # Requeue all running slices for a server or worker that is no longer available
      def requeue_running(worker_name)
        running.where(worker_name: /\A#{worker_name}/).update_all(
          "$unset" => {worker_name: nil, started_at: nil},
          "$set"   => {state: "queued"}
        )
      end

      # Claims and returns the next queued slice for this worker.
      # Returns nil if there are currently no queued slices.
      #
      # No explicit sort is applied. Forcing the global minimum `_id` (a
      # `sort("_id" => 1)`) makes every worker target the same document, so under
      # concurrency they collide on the atomic claim: one wins and the rest hit a
      # WriteConflict ("Document no longer matches the predicate") and retry,
      # which throttles a large batch job as workers are added. Without the sort,
      # the `{state: 1, _id: 1}` index still yields queued slices in roughly `_id`
      # (upload) order, but concurrent workers land on different documents instead
      # of contending for one. Output ordering is unaffected: each output slice
      # inherits its input slice's `_id` and downloads read in `_id` order.
      def next_slice(worker_name)
        document                 = all.queued.
                                   find_one_and_update(
                                     {"$set" => {worker_name: worker_name, state: "running", started_at: Time.now}},
                                     return_document: :after
                                   )
        document.collection_name = collection_name if document
        document
      end
    end
  end
end

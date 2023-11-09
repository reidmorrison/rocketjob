module RocketJob
  module Sliced
    class Input < Slices
      def upload(**args, &block)
        # Create indexes before uploading
        create_indexes
        Writer::Input.collect(self, **args, &block)
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

      # Returns the next slice to work on in id order
      # Returns nil if there are currently no queued slices
      #
      # If a slice is in queued state it will be started and assigned to this worker
      def next_slice(worker_name)
        # TODO: Will it perform faster without the id sort?
        # I.e. Just process on a FIFO basis?
        document                 = all.queued.
          sort("_id" => 1).
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

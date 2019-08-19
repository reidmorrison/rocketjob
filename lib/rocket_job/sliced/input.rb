module RocketJob
  module Sliced
    class Input < Slices
      def upload(file_name_or_io = nil, encoding: 'UTF-8', stream_mode: :line, on_first: nil, **args, &block)
        raise(ArgumentError, 'Either file_name_or_io, or a block must be supplied') unless file_name_or_io || block

        block ||= -> (io) do
          iterator = "each_#{stream_mode}".to_sym
          IOStreams.public_send(iterator, file_name_or_io, encoding: encoding, **args) { |line| io << line }
        end

        Writer::Input.collect(self, on_first: on_first, &block)
      end

      def upload_mongo_query(criteria, *column_names, &block)
        options = criteria.options

        # Without a block extract the fields from the supplied criteria
        if block
          # Criteria is returning old school :fields instead of :projections
          options[:projection] = options.delete(:fields) if options.key?(:fields)
        else
          column_names = column_names.collect(&:to_s)
          column_names << '_id' if column_names.size.zero?

          fields = options.delete(:fields) || {}
          column_names.each { |col| fields[col] = 1 }
          options[:projection] = fields

          block =
            if column_names.size == 1
              column = column_names.first
              ->(document) { document[column] }
            else
              ->(document) { column_names.collect { |c| document[c] } }
            end
        end

        Writer::Input.collect(self) do |records|
          # Drop down to the mongo driver level to avoid constructing a Model for each document returned
          criteria.klass.collection.find(criteria.selector, options).each do |document|
            records << block.call(document)
          end
        end
      end

      def upload_arel(arel, *column_names, &block)
        unless block
          column_names = column_names.collect(&:to_sym)
          column_names << :id if column_names.size.zero?

          block =
            if column_names.size == 1
              column = column_names.first
              ->(model) { model.send(column) }
            else
              ->(model) { column_names.collect { |c| model.send(c) } }
            end
          # find_each requires the :id column in the query
          selection = column_names.include?(:id) ? column_names : column_names + [:id]
          arel      = arel.select(selection)
        end

        Writer::Input.collect(self) do |records|
          arel.find_each { |model| records << block.call(model) }
        end
      end

      def upload_integer_range(start_id, last_id)
        create_indexes
        count = 0
        while start_id <= last_id
          end_id = start_id + slice_size - 1
          end_id = last_id if end_id > last_id
          create!(records: [[start_id, end_id]])
          start_id += slice_size
          count    += 1
        end
        count
      end

      def upload_integer_range_in_reverse_order(start_id, last_id)
        create_indexes
        end_id = last_id
        count  = 0
        while end_id >= start_id
          first_id = end_id - slice_size + 1
          first_id = start_id if first_id.negative? || (first_id < start_id)
          create!(records: [[first_id, end_id]])
          end_id -= slice_size
          count  += 1
        end
        count
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
          '$unset' => {worker_name: nil, started_at: nil},
          '$set'   => {state: :queued}
        )
      end

      # Requeue all running slices for a server or worker that is no longer available
      def requeue_running(worker_name)
        running.where(worker_name: /\A#{worker_name}/).update_all(
          '$unset' => {worker_name: nil, started_at: nil},
          '$set'   => {state: :queued}
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
          sort('_id' => 1).
          find_one_and_update(
            {'$set' => {worker_name: worker_name, state: :running, started_at: Time.now}},
            return_document: :after
          )
        document.collection_name = collection_name if document
        document
      end
    end
  end
end

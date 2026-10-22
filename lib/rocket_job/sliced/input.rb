module RocketJob
  module Sliced
    class Input < Slices
      # Uploads the records that the block writes, see Writer::Input.collect, and returns how many it wrote.
      #
      # When the upload raises, its slices are removed, and the slices of earlier uploads are kept: those of the
      # supplied `upload_id`, or when the collection already holds slices, of an id of its own, otherwise the whole
      # collection, so that the slices of the first upload do not each hold an id.
      def upload(upload_id: nil, **args, &)
        # Create indexes before uploading
        create_indexes
        upload_id = BSON::ObjectId.new.to_s if upload_id.nil? && count.positive?
        Writer::Input.collect(self, upload_id: upload_id, **args, &)
      rescue Exception => e
        upload_id ? delete_upload(upload_id) : drop
        raise(e)
      end

      # Removes the slices of the upload with the supplied id, see Slice#upload_id.
      def delete_upload(upload_id)
        where(upload_id: upload_id).delete_all
      end

      # Uploads the documents of the supplied Mongoid criteria, read with the driver of MongoDB without building a model
      # for each one: the value of the field of each document when one field is uploaded, by default its `_id`,
      # otherwise an Array of the values of the fields. Returns how many it uploaded.
      #
      # The documents are those that Mongoid's own query of the criteria returns, see `Mongoid::Contextual::Mongo#view`:
      # from the collection that Mongoid reads it from, of the class of the criteria only, rather than its parent's too,
      # and in its order and within its limit. The criteria of the caller is not changed. A field is read by the name
      # that it is stored by, so that the field that `as:` aliases is read by its alias.
      def upload_mongo_query(criteria, columns: [], slice_batch_size: nil, upload_id: nil)
        columns = columns.blank? ? ["_id"] : columns.collect { |column| criteria.klass.database_field_name(column) }
        view    = criteria.only(*columns).context.view

        upload(slice_batch_size: slice_batch_size, upload_id: upload_id) do |records|
          # Drop down to the mongo driver level to avoid constructing a Model for each document returned
          view.each do |document|
            records << (columns.size == 1 ? document[columns.first] : columns.collect { |c| document[c] })
          end
        end
      end

      # Uploads the rows of the supplied Active Record relation, which IOStreams reads as one query that the database
      # streams, without building a model for each row, see `IOStreams.stream`, or the rows of the batches that
      # `relation.in_batches(...)` returns, which IOStreams reads in those batches, for a database that cannot stream a
      # query: the value of each row when it has one column, otherwise an Array of its values. A relation reads the
      # supplied columns, by default the id, and batches read the columns that their relation selects. Returns how many
      # it uploaded.
      #
      # Raises ArgumentError for columns supplied with batches, whose relation selects the columns instead, and for
      # batches whose relation selects no columns, which would upload every column of each row, where a relation
      # uploads only the id.
      def upload_arel(query, columns: nil, slice_batch_size: nil, upload_id: nil)
        if query.is_a?(ActiveRecord::Batches::BatchEnumerator)
          if columns.present?
            raise(ArgumentError, "Select the columns to upload before `in_batches`, rather than with `columns:`")
          end
          if query.relation.select_values.empty?
            raise(ArgumentError, "Select the columns to upload before `in_batches`, such as " \
                                 "`relation.select(:id).in_batches`")
          end
        else
          # Symbols, since Active Record quotes a Symbol as the name of a column, but runs a String as SQL.
          query = query.reselect(*(columns.presence || [:id]).collect(&:to_sym))
        end

        stream = IOStreams.stream(query)
        upload(slice_batch_size: slice_batch_size, upload_id: upload_id) do |records|
          record = nil
          stream.each(:array) do |row|
            if record
              records << record.call(row)
            else
              # The first row is the header row of the names of the columns.
              record = row.size == 1 ? :first.to_proc : :itself.to_proc
            end
          end
        end
      end

      def upload_integer_range(start_id, last_id, slice_batch_size: 1_000, upload_id: nil)
        # Each "record" is actually a range of Integers which makes up each slice
        upload(slice_size: 1, slice_batch_size: slice_batch_size, upload_id: upload_id) do |records|
          while start_id <= last_id
            end_id = start_id + slice_size - 1
            end_id = last_id if end_id > last_id
            records << [start_id, end_id]
            start_id += slice_size
          end
        end
      end

      def upload_integer_range_in_reverse_order(start_id, last_id, slice_batch_size: 1_000, upload_id: nil)
        # Each "record" is actually a range of Integers which makes up each slice
        upload(slice_size: 1, slice_batch_size: slice_batch_size, upload_id: upload_id) do |records|
          end_id = last_id
          while end_id >= start_id
            first_id = end_id - slice_size + 1
            first_id = start_id if first_id < start_id
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

      # Requeue all running slices of the workers on a server that is no longer available, or of the named worker,
      # see RocketJob::Worker.on_server?, or every running slice when no server is named.
      def requeue_running(server_name)
        slices = server_name ? running.where(worker_name: RocketJob::Worker.on_server_pattern(server_name)) : running
        slices.update_all(
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

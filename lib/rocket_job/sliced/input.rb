module RocketJob
  module Sliced
    class Input < Slices
      # Yields the store of slices of this input, see Writer::Input.collect, which IOStreams writes the slices of the
      # upload to, see `IOStreams::Slice::Target`, or the records of a category without a format are written to one at
      # a time, see Writer::Input#<<, and returns how many records they hold.
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
      # for each one, as the rows of the fields, by default its `_id`, which the supplied input category writes, see
      # Category::Input#write_rows: in its format, after the names of the fields, otherwise the value of the field of
      # each document when one field is uploaded, or an Array of the values of the fields. Returns how many it uploaded.
      #
      # The documents are those that Mongoid's own query of the criteria returns, see `Mongoid::Contextual::Mongo#view`:
      # from the collection that Mongoid reads it from, of the class of the criteria and its subclasses only, rather
      # than its parent's too, and in its order and within its limit. None are uploaded for a criteria that Mongoid
      # knows returns none without a query, such as `criteria.none`. The criteria of the caller is not changed.
      #
      # A field is read by the name that it is stored by, so that the field that `as:` aliases is read by its alias, and
      # a dotted name reads the field of an embedded document, such as `address.city`, or of each of a list of them, as
      # an Array. The columns replace any projection of the criteria, such as `without(:secret)`.
      #
      # The documents are read outside any session or transaction of the caller, so that a large upload is not bound by
      # the time limit of a transaction. Raises ArgumentError for a criteria of embedded documents, which are read
      # within the documents that embed them rather than queried.
      def upload_mongo_query(criteria, category:, columns: [], slice_batch_size: nil, upload_id: nil)
        columns = columns.blank? ? ["_id"] : columns.collect { |column| criteria.klass.database_field_name(column) }
        view    = mongo_query_view(criteria, columns)
        paths   = columns.collect { |column| column.split(".") }

        upload(slice_batch_size: slice_batch_size, upload_id: upload_id) do |writer|
          category.write_rows(writer) do |rows|
            rows.write_header(columns)
            # Drop down to the mongo driver level to avoid constructing a Model for each document returned
            view&.each do |document|
              rows << paths.collect { |path| mongo_value(document, path) }
            end
          end
        end
      end

      # Uploads the rows of the supplied Active Record relation, which IOStreams reads as one query that the database
      # streams, without building a model for each row, see `IOStreams.stream`, or the rows of the batches that
      # `relation.in_batches(...)` returns, which IOStreams reads in those batches, for a database that cannot stream a
      # query, which the supplied input category writes, see Category::Input#copy_rows: in its format, as a file of the
      # query would hold them, otherwise the value of each row when it has one column, or an Array of its values. A
      # relation reads the supplied columns, by default the id, and batches read the columns that their relation
      # selects. Returns how many it uploaded.
      #
      # Raises ArgumentError for columns supplied with batches, whose relation selects the columns instead, and for
      # batches whose relation selects no columns, which would upload every column of each row, where a relation
      # uploads only the id.
      def upload_arel(query, category:, columns: nil, slice_batch_size: nil, upload_id: nil)
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
        upload(slice_batch_size: slice_batch_size, upload_id: upload_id) do |writer|
          category.copy_rows(stream, writer)
        end
      end

      # Uploads the supplied ids as one `[first_id, last_id]` record per slice, of up to `slice_size` ids each, which
      # IOStreams writes to the slices as it is, without a format, see #upload_ranges.
      def upload_integer_range(start_id, last_id, slice_batch_size: 1_000, upload_id: nil)
        upload_ranges(slice_batch_size, upload_id) do |ranges|
          while start_id <= last_id
            end_id = start_id + slice_size - 1
            end_id = last_id if end_id > last_id
            ranges << [start_id, end_id]
            start_id += slice_size
          end
        end
      end

      # Uploads the supplied ids as #upload_integer_range does, starting with the last slice.
      def upload_integer_range_in_reverse_order(start_id, last_id, slice_batch_size: 1_000, upload_id: nil)
        upload_ranges(slice_batch_size, upload_id) do |ranges|
          end_id = last_id
          while end_id >= start_id
            first_id = end_id - slice_size + 1
            first_id = start_id if first_id < start_id
            ranges << [first_id, end_id]
            end_id -= slice_size
          end
        end
      end

      # Yields the writer of the ranges of ids, each `[first_id, last_id]`, which IOStreams writes one per slice, as the
      # typed row of a store of slices in the :array format, without a header row, see RANGE_SCHEMA.
      def upload_ranges(slice_batch_size, upload_id, &)
        upload(slice_size: 1, slice_batch_size: slice_batch_size, upload_id: upload_id) do |writer|
          IOStreams.stream(writer).format(:array).schema(RANGE_SCHEMA).writer(:array, &)
        end
      end
      private :upload_ranges

      # The fields of the `[first_id, last_id]` row of each range of ids, see #upload_ranges, without a header row, so
      # that each slice holds the range as it is, which a worker passes to `#perform` as it is.
      RANGE_SCHEMA = {
        "header" => false,
        "fields" => [
          {"name" => "first_id", "type" => "integer"},
          {"name" => "last_id", "type" => "integer"}
        ]
      }.freeze
      private_constant :RANGE_SCHEMA

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

      private

      # The driver's view of the documents that Mongoid's query of the criteria returns, with only the supplied
      # columns, without the session of the caller. Nil when Mongoid knows without a query that it returns none.
      def mongo_query_view(criteria, columns)
        # A copy, so that the criteria of the caller is not changed. Its projection is dropped, since the columns say
        # what to read, and MongoDB rejects the columns merged into a projection that excludes fields.
        query = criteria.clone
        query.options.delete(:fields)
        context = query.only(*columns).context
        return if context.is_a?(Mongoid::Contextual::None)

        unless context.is_a?(Mongoid::Contextual::Mongo)
          raise(ArgumentError, "Upload a query of the documents that embed #{criteria.klass.name}, since embedded " \
                               "documents are read within them rather than queried")
        end

        view    = context.view
        options = view.options.dup
        options.delete(:session)
        view.collection.find(view.filter, options)
      end

      # The value at the path of the names of the fields within the document, or an Array of the values within each
      # document of an Array, such as `items.name` of `embeds_many :items`.
      def mongo_value(value, path)
        case value
        when Hash
          path.size == 1 ? value[path.first] : mongo_value(value[path.first], path.drop(1))
        when Array
          value.collect { |element| mongo_value(element, path) }
        end
      end
    end
  end
end

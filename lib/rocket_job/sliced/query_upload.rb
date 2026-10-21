module RocketJob
  module Sliced
    # The rows of an Active Record query that an upload stores, see RocketJob::Batch::IO#upload, which IOStreams reads
    # from the database without building a model for each row, see `IOStreams.stream`. A relation is read as one query,
    # streamed, so its order and limit are kept, and a sorted or grouped query runs once. The batches of a relation,
    # which `relation.in_batches(...)` returns, are read in those batches instead, as Rails reads them, so that a
    # database whose driver cannot stream a query can be read.
    #
    # It knows the columns that are read: those that `columns:` names, otherwise the primary key of the model of the
    # relation for the records that are uploaded, see #each_value and #each_slice, or the columns that the relation
    # selects for the rows that a block receives, see #each_row, and how to read only them, whether it was given a
    # relation or its batches. Each value is cast as `pluck` casts it, rather than read with a reader of the model.
    #
    # A relation is read on a connection of its own, see `IOStreams::Query#open`, so its rows are those that were
    # committed, rather than those that an open transaction of the caller wrote. Its batches are read on the connection
    # of the caller, each batch whole, as Rails reads them, so they include those rows.
    #
    # Reading the rows raises ArgumentError, before any row is read, for a query that IOStreams cannot read, such as a
    # relation that loads the associations of its models with `includes`, or a relation on a database whose driver
    # cannot stream a query, or for batches that do not select a column that is read, see #column_indexes.
    class QueryUpload
      # The number of rows that are read from IOStreams at a time, see #each_value and #each_row, which has no effect
      # on how many rows the database returns at a time, or on the size of a slice.
      READ_SIZE = 1_000
      private_constant :READ_SIZE

      # Returns [true|false] whether the supplied object is an Active Record query that an upload reads the rows of: a
      # relation, or the batches of one that `relation.in_batches` returns without a block. False while Active Record
      # is not loaded, since no object can then be one.
      def self.query?(object)
        return false unless defined?(ActiveRecord::Relation)

        object.is_a?(ActiveRecord::Relation) || object.is_a?(ActiveRecord::Batches::BatchEnumerator)
      end

      # Parameters
      #   query: [ActiveRecord::Relation|ActiveRecord::Batches::BatchEnumerator]
      #     The relation whose rows are uploaded, or the batches of one, which `relation.in_batches(...)` returns.
      #
      #   columns: [Array<Symbol|String>]
      #     The columns to read.
      #     Default: the primary key of the model of the relation, such as `[:id]`, for the records that are uploaded,
      #     or the columns that the relation selects for the rows that a block receives, see #each_row.
      def initialize(query, columns: nil)
        @batches        = query if query.is_a?(ActiveRecord::Batches::BatchEnumerator)
        @relation       = @batches ? @batches.relation : query
        @columns        = columns.collect(&:to_sym) if columns.present?
        @streams        = {}
      end

      # Returns [true|false] whether one column is uploaded, whose value is the record of each row, see #each_value,
      # rather than several, whose rows are uploaded in slices, see #each_slice.
      #
      # Raises ArgumentError, as do the other methods that read the columns that are uploaded, when no columns were
      # supplied, and the model has no primary key, see #record_columns.
      def single_column?
        record_columns.size == 1
      end

      # Yields the value of the column of each row, when one column is uploaded, see #single_column?.
      #
      # Raises ArgumentError when several columns are uploaded, whose rows are uploaded in slices, see #each_slice.
      def each_value
        unless single_column?
          raise(ArgumentError, "Several columns are uploaded in slices of their rows, see #each_slice, not as values")
        end

        each_slice_of(record_columns, size: READ_SIZE) do |slice|
          slice.each { |row| yield(row.first) }
        end
      end

      # Yields [IOStreams::Slice] each slice of the rows of the columns that are uploaded, of up to the supplied number of
      # rows: the values of the columns of each row, in the `:array` format, after the header row of their names, see
      # #column_names, so that whoever reads them reads each row as a Hash of the columns by name. Each of its rows is a
      # record, see `IOStreams::Slice#blank_rows?`, so a row whose every value is null is read as one.
      def each_slice(size:, &)
        each_slice_of(record_columns, size: size, &)
      end

      # Returns [Array<String>] the names of the columns that are uploaded, as the query names them, such as "name" for
      # a column that `alias_attribute :full_name, :name` aliases, which is the header row of each slice, see
      # #each_slice.
      def column_names
        fields_of(record_columns).collect { |field| field.fetch(:name) }
      end

      # Returns [Hash] the schema of the columns that are uploaded, see #each_slice, which a query of no rows describes,
      # with the type of each column, see `IOStreams::Query::Stream#schema`, by String keys, as a category holds it.
      def schema
        stream_of(record_columns).schema.merge(fields: fields_of(record_columns)).deep_stringify_keys
      end

      # Yields [Hash] each row of the query, by the names of its columns, as Strings, such as
      # `{"id" => 1, "email" => "jack@example.com"}`, without building a model: the columns that `columns:` names,
      # otherwise those that the relation selects, which is every column of its table unless it says otherwise.
      def each_row
        each_slice_of(@columns, size: READ_SIZE) do |slice|
          names = slice.header
          slice.each { |row| yield(names.zip(row).to_h) }
        end
      end

      private

      # Returns [Array<Symbol>] the columns that are uploaded: those that `columns:` names, otherwise the primary key of
      # the model, which is only looked for here, since the rows that a block receives need none, see #each_row.
      def record_columns
        @record_columns ||= @columns || primary_key_columns(@relation.klass)
      end

      # Yields [IOStreams::Slice] each slice of the rows of the supplied columns, or of every column that the query
      # selects when none are supplied, see #each_slice. A relation selects only the supplied columns, as `pluck` does,
      # see `ActiveRecord::QueryMethods#reselect`. The batches of a relation each select what the relation selects,
      # which Rocket Job cannot change without losing their settings, such as their `cursor:`, so each of their slices
      # is narrowed to the supplied columns, which are found by their names, see #column_indexes.
      def each_slice_of(columns, size:)
        indexes = column_indexes(columns) if @batches && columns
        names   = fields_of(columns).collect { |field| field.fetch(:name) }.freeze if indexes
        stream_of(columns).each(:slice, size: size) do |slice|
          next yield(slice) unless indexes

          rows = slice.map { |row| row.values_at(*indexes) }
          yield(IOStreams::Slice.new(rows, header: names, format: slice.format, blank_rows: slice.blank_rows?))
        end
      end

      # Returns [Array<Hash>] the fields of the schema of the supplied columns, see #each_slice_of, as the stream of the
      # query describes them, see `IOStreams::Query::Stream#schema`, in the order of the columns.
      def fields_of(columns)
        fields = stream_of(columns).schema.fetch(:fields)
        @batches && columns ? fields.values_at(*column_indexes(columns)) : fields
      end

      # Returns [IOStreams::Query::Stream] the stream of the rows of the supplied columns, see #each_slice_of, which
      # describes its columns once, see `IOStreams::Query#columns`.
      def stream_of(columns)
        @streams[columns] ||= IOStreams.stream(@batches || (columns ? @relation.reselect(*columns) : @relation))
      end

      # Returns [Array<Integer>] the position of each of the supplied columns among the columns that the batches of the
      # relation read, which a query of no rows describes, see `IOStreams::Query#columns`, so that a column that the
      # relation does not select raises before any batch is read. A column of the model that another name aliases, see
      # `alias_attribute`, is found by the name of its column.
      #
      # Raises ArgumentError for a column that the relation does not select.
      def column_indexes(columns)
        model = @relation.klass
        names = stream_of(columns).schema.fetch(:fields).collect { |field| field.fetch(:name) }
        columns.collect do |column|
          name = model.attribute_alias?(column) ? model.attribute_alias(column) : column.to_s
          names.index(name) ||
            raise(ArgumentError, "The batches of the #{model.name} query do not select the column #{column}, which " \
                                 "is read: select it before `in_batches`, or upload the relation instead")
        end
      end

      # Returns [Array<Symbol>] the columns of the primary key of the supplied model, such as `[:id]`, or each column of
      # a composite primary key.
      #
      # Raises ArgumentError when the model has none, such as the model of a database view.
      def primary_key_columns(model)
        columns = Array(model.primary_key)
        if columns.empty?
          raise(ArgumentError, "#{model.name} has no primary key, so name the columns to upload with `columns:`")
        end

        columns.collect(&:to_sym)
      end
    end
  end
end

module RocketJob
  module Sliced
    # The records of an Active Record query that an upload stores, see RocketJob::Batch::IO#upload: the values of the
    # columns that it uploads, which IOStreams reads from the database without building a model for each row, see
    # `IOStreams.stream`. A relation is read as one query, streamed, so its order and limit are kept, and a sorted or
    # grouped query runs once. The batches of a relation, which `relation.in_batches(...)` returns, are read in those
    # batches instead, as Rails reads them, so that a database whose driver cannot stream a query can be read.
    #
    # It knows the columns that are uploaded: those that `columns:` names, otherwise the primary key of the model of the
    # relation, and how to read only them, whether it was given a relation or its batches. Each value is cast as `pluck`
    # casts it, rather than read with a reader of the model.
    class QueryUpload
      # The number of rows that are read from IOStreams at a time, see #each_record, which has no effect on how many
      # rows the database returns at a time, or on the size of a slice.
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
      #     The columns to upload.
      #     Default: the primary key of the model of the relation, such as `[:id]`.
      #
      # Raises ArgumentError when no columns are supplied, and the model has no primary key.
      def initialize(query, columns: nil)
        @batches  = query if query.is_a?(ActiveRecord::Batches::BatchEnumerator)
        @relation = @batches ? @batches.relation : query
        @columns  = columns.blank? ? primary_key_columns(@relation.klass) : columns.collect(&:to_sym)
      end

      # Yields the record of each row of the query: the value of its column when one column is uploaded, otherwise an
      # Array of the values of its columns, in the order of the columns.
      #
      # A relation is read on a connection of its own, see `IOStreams::Query#open`, so its rows are those that were
      # committed, rather than those that an open transaction of the caller wrote. Its batches are read on the
      # connection of the caller, each batch whole, as Rails reads them, so they include those rows.
      #
      # Raises ArgumentError, before any row is read, for a query that IOStreams cannot read, such as a relation that
      # loads the associations of its models with `includes`, or a relation on a database whose driver cannot stream a
      # query, or for batches that do not select a column that is uploaded, see #column_indexes.
      def each_record
        single = @columns.size == 1
        each_values { |values| yield(single ? values.first : values) }
      end

      # Yields each model of the query, which `find_each` reads for a relation, in the order of its primary key, and
      # `each_record` of its batches, see `ActiveRecord::Batches::BatchEnumerator#each_record`.
      def each_model(&)
        @batches ? @batches.each_record(&) : @relation.find_each(&)
      end

      private

      # Yields [Array] the values of the columns that are uploaded of each row, in the order of the columns. A relation
      # selects only them, as `pluck` does, see `ActiveRecord::QueryMethods#reselect`. The batches of a relation each
      # select what the relation selects, which Rocket Job cannot change without losing their settings, such as their
      # `cursor:`, so the values are taken from each row by the names of the columns, see #column_indexes.
      def each_values
        stream  = IOStreams.stream(@batches || @relation.reselect(*@columns))
        indexes = column_indexes(stream) if @batches
        stream.each(:slice, size: READ_SIZE) do |slice|
          slice.each { |row| yield(indexes ? row.values_at(*indexes) : row) }
        end
      end

      # Returns [Array<Integer>] the position of each column that is uploaded among the columns that the supplied stream
      # of the batches of a relation reads, which a query of no rows describes, see `IOStreams::Query#columns`, so that
      # a column that the relation does not select raises before any batch is read. A column of the model that another
      # name aliases, see `alias_attribute`, is found by the name of its column.
      #
      # Raises ArgumentError for a column that the relation does not select.
      def column_indexes(stream)
        model = @relation.klass
        names = stream.schema.fetch(:fields).collect { |field| field.fetch(:name) }
        @columns.collect do |column|
          name = model.attribute_alias?(column) ? model.attribute_alias(column) : column.to_s
          names.index(name) ||
            raise(ArgumentError, "The batches of the #{model.name} query do not select the column #{column}, which " \
                                 "is uploaded: select it before `in_batches`, or upload the relation instead")
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

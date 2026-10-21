module RocketJob
  module Sliced
    # The records of an Active Record relation that an upload stores, see RocketJob::Batch::IO#upload: the values of the
    # columns that it uploads, which IOStreams reads from the database as one query, streamed, without building a model
    # for each row, see `IOStreams.stream`. So the order and the limit of the relation are kept, and a sorted or grouped
    # query runs once.
    #
    # It knows the columns that are uploaded: those that `columns:` names, otherwise the primary key of the model of the
    # relation. Only they are selected, as `pluck` selects them, see `ActiveRecord::QueryMethods#reselect`, and each value
    # is cast as `pluck` casts it, rather than read with a reader of the model.
    class QueryUpload
      # The number of rows that are read from IOStreams at a time, see #each_record, which has no effect on how many
      # rows the database returns at a time, or on the size of a slice.
      READ_SIZE = 1_000
      private_constant :READ_SIZE

      # Parameters
      #   relation: [ActiveRecord::Relation]
      #     The relation whose rows are uploaded.
      #
      #   columns: [Array<Symbol|String>]
      #     The columns to upload.
      #     Default: the primary key of the model of the relation, such as `[:id]`.
      #
      # Raises ArgumentError when no columns are supplied, and the model has no primary key.
      def initialize(relation, columns: nil)
        @relation = relation
        @columns  = columns.blank? ? primary_key_columns(relation.klass) : columns.collect(&:to_sym)
      end

      # Yields the record of each row of the relation: the value of its column when one column is uploaded, otherwise
      # an Array of the values of its columns, in the order of the columns.
      #
      # The rows are read on a connection of their own, see `IOStreams::Query#open`, so they are the rows that were
      # committed, rather than those that an open transaction of the caller wrote.
      #
      # Raises ArgumentError, before any row is read, for a relation that IOStreams cannot read, such as one that
      # loads the associations of its models with `includes`, or on a database whose driver cannot stream a query.
      def each_record
        single = @columns.size == 1
        IOStreams.stream(@relation.reselect(*@columns)).each(:slice, size: READ_SIZE) do |slice|
          slice.each { |row| yield(single ? row.first : row) }
        end
      end

      private

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

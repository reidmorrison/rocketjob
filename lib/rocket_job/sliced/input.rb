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

      # Uploads the documents of the supplied Mongoid criteria, see Batch::IO#upload, and returns how many it uploaded.
      #
      # Reports a deprecation warning, see QueryDeprecation, for what Rocket Job 8 uploads differently, without
      # changing what this upload stores.
      def upload_mongo_query(criteria, columns: [], slice_batch_size: nil, &block)
        QueryDeprecation.warn_criteria(block)
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

      # Uploads the rows of the supplied Active Record relation, see Batch::IO#upload, and returns how many it uploaded.
      #
      # Reports a deprecation warning, see QueryDeprecation, for what Rocket Job 8 uploads differently, without
      # changing what this upload stores.
      def upload_arel(arel, columns: nil, slice_batch_size: nil, &block)
        QueryDeprecation.warn_relation(arel, block)
        unless block
          columns = columns.blank? ? [:id] : columns.collect(&:to_sym)

          block =
            if columns.size == 1
              column = columns.first
              ->(model) { model.public_send(column) }
            else
              ->(model) { columns.collect { |c| model.public_send(c) } }
            end
          block = QueryDeprecation.check_readers(columns, block)
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

      # Knows what Rocket Job 8 changes in uploading a query, and reports a deprecation warning, see
      # RocketJob::Deprecation, for each change that an upload depends on, so that the upload methods above only upload
      # as 7.x does, and store exactly what they stored before.
      #
      # Rocket Job 8 reads an Active Record relation in one streamed query, with each value cast as `pluck` casts it,
      # and builds no models, so:
      # - A block passed with a query, a relation or a Mongoid criteria, raises ArgumentError: the block of `upload`
      #   writes the records instead, such as those of a query that it reads itself.
      # - A relation that eager loads its associations, with `includes`, `preload` or `eager_load`, raises
      #   ArgumentError.
      # - Each column uploads the value that it holds, as `pluck` returns it, rather than calling the reader of the
      #   model, which differs only when the model overrides the reader.
      #
      # The records of one column, the value of each row, and of several, an Array of their values, are unchanged.
      #
      # An upload reports each change that it depends on once, and the reader of each column at most once.
      class QueryDeprecation
        # The methods of a relation that eager load its associations, which Rocket Job 8 cannot upload.
        EAGER_LOADING = %i[includes preload eager_load].freeze

        # Reports a deprecation warning for each change that the upload of the supplied Active Record relation, or
        # model class, depends on: that it eager loads associations, and that the supplied block is passed with it.
        #
        # Returns nil.
        def self.warn_relation(relation, block)
          warn_eager_loading(relation)
          warn_block("an Active Record relation", "User.where(country_code: \"US\").find_each") if block
          nil
        end

        # Reports a deprecation warning when the supplied block is passed with the upload of a Mongoid criteria.
        #
        # Returns nil.
        def self.warn_criteria(block)
          warn_block("a Mongoid criteria", "User.where(state: \"FL\").each") if block
          nil
        end

        # Reports a deprecation warning that a block passed with the supplied kind of query raises in Rocket Job 8, with
        # an example that reads the query in the block of `upload` instead.
        def self.warn_block(kind, query)
          RocketJob::Deprecation.warn(
            "a block passed with #{kind} raises ArgumentError in Rocket Job 8, which uploads the values of its " \
            "columns: write the records in the block of upload instead, such as " \
            "job.upload { |records| #{query} { |user| records << user.email.downcase } }, see " \
            "#{RocketJob::Deprecation::UPGRADE_GUIDE}"
          )
        end
        private_class_method :warn_block

        # Returns [Proc] the supplied block, which returns the record that 7.x uploads for a model, while deprecation
        # warnings are off, so that production does not pay for checking every model. Otherwise returns a Proc that
        # also checks each model, after the block has read it, for a reader of one of the supplied columns that
        # returns a value other than the one that the column holds, see #check.
        def self.check_readers(columns, block)
          return block unless RocketJob::Deprecation.enabled?

          readers = new(columns)
          lambda do |model|
            record = block.call(model)
            readers.check(model)
            record
          end
        end

        # Reports a deprecation warning, naming the methods, when the supplied relation, or model class, such as one
        # with a default scope, eager loads its associations.
        def self.warn_eager_loading(relation)
          return unless relation.respond_to?(:all)

          scope   = relation.all
          methods = EAGER_LOADING.select { |name| scope.public_send(:"#{name}_values").present? }
          return if methods.empty?

          # Without the connectors of the application's locale, so that the message is the same in every application.
          names = methods.to_sentence(last_word_connector: " and ", locale: false)
          RocketJob::Deprecation.warn(
            "uploading an Active Record relation that uses #{names} raises ArgumentError in Rocket Job 8, which reads " \
            "the rows of one query and builds no models: join the tables with joins and select their columns instead, " \
            "or to filter by an association, use joins with distinct, or a subquery, see " \
            "#{RocketJob::Deprecation::UPGRADE_GUIDE}"
          )
        end
        private_class_method :warn_eager_loading

        # The supplied columns, whose readers are checked.
        def initialize(columns)
          @columns = columns.dup
        end

        # Reports a deprecation warning for each column whose reader on the supplied model returns a value other than
        # the one that the column holds, see ActiveRecord::AttributeMethods::Read#read_attribute, which is what `pluck`
        # returns, and what Rocket Job 8 uploads. Then stops checking that column, so that each column warns at most
        # once. Names the model class and the column, but never the values, which could be personal data.
        #
        # The reader is called again to compare it, after the upload has read the model, so the record uploaded is the
        # one that the upload would store without the check.
        #
        # Returns nil.
        def check(model)
          @columns.reject! do |column|
            next false if model.public_send(column) == model.read_attribute(column)

            RocketJob::Deprecation.warn(
              "#{model.class}##{column} returns a value other than the one that its column holds, which Rocket Job 8 " \
              "uploads instead, as pluck returns it, rather than calling the reader: to keep the reader's value, write " \
              "the records in the block of upload, which can call it, or apply the reader's logic in perform, see " \
              "#{RocketJob::Deprecation::UPGRADE_GUIDE}"
            )
            true
          end
          nil
        end
      end
      private_constant :QueryDeprecation
    end
  end
end

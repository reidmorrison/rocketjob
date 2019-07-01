module RocketJob
  module Sliced
    class Input < Slices
      # Load lines for processing from the supplied filename or stream into this job.
      #
      # Returns [Integer] the number of lines loaded into this collection
      #
      # Parameters
      #   file_name_or_io [String | IO]
      #     Full path and file name to stream into the job,
      #     Or, an IO Stream that responds to: :read
      #
      #   streams [Symbol|Array]
      #     Streams to convert the data whilst it is being read.
      #     When nil, the file_name extensions will be inspected to determine what
      #     streams should be applied.
      #     Default: nil
      #
      #   delimiter[String]
      #     Line / Record delimiter to use to break the stream up into records
      #       Any string to break the stream up by
      #       The records when saved will not include this delimiter
      #     Default: nil
      #       Automatically detect line endings and break up by line
      #       Searches for the first "\r\n" or "\n" and then uses that as the
      #       delimiter for all subsequent records
      #
      #   buffer_size [Integer]
      #     Size of the blocks when reading from the input file / stream.
      #     Default: 65536 ( 64K )
      #
      #   encoding: [String|Encoding]
      #     Encode returned data with this encoding.
      #     'US-ASCII':   Original 7 bit ASCII Format
      #     'ASCII-8BIT': 8-bit ASCII Format
      #     'UTF-8':      UTF-8 Format
      #     Etc.
      #     Default: 'UTF-8'
      #
      #   encode_replace: [String]
      #     The character to replace with when a character cannot be converted to the target encoding.
      #     nil: Don't replace any invalid characters. Encoding::UndefinedConversionError is raised.
      #     Default: nil
      #
      #   encode_cleaner: [nil|symbol|Proc]
      #     Cleanse data read from the input stream.
      #     nil:           No cleansing
      #     :printable Cleanse all non-printable characters except \r and \n
      #     Proc/lambda    Proc to call after every read to cleanse the data
      #     Default: :printable
      #
      #   stream_mode: [:line | :row | :record]
      #     :line
      #       Uploads the file a line (String) at a time for processing by workers.
      #     :row
      #       Parses each line from the file as an Array and uploads each array for processing by workers.
      #     :record
      #       Parses each line from the file into a Hash and uploads each hash for processing by workers.
      #     See IOStream#each_line, IOStream#each_row, and IOStream#each_record.
      #
      # Example:
      #   # Load plain text records from a file
      #   job.input.upload('hello.csv')
      #
      # Example:
      #   # Load plain text records from a file, stripping all non-printable characters,
      #   # as well as any characters that cannot be converted to UTF-8
      #   job.input.upload('hello.csv', encode_cleaner: :printable, encode_replace: '')
      #
      # Example: Zip
      #   # Since csv is not known to RocketJob it is ignored
      #   job.input.upload('myfile.csv.zip')
      #
      # Example: Encrypted Zip
      #   job.input.upload('myfile.csv.zip.enc')
      #
      # Example: Explicitly set the streams
      #   job.input.upload('myfile.ze', streams: [:zip, :enc])
      #
      # Example: Supply custom options
      #   job.input.upload('myfile.csv.enc', streams: :enc])
      #
      # Example: Extract streams from filename but write to a temp file
      #   streams = IOStreams.streams_for_file_name('myfile.gz.enc')
      #   t = Tempfile.new('my_project')
      #   job.input.upload(t.to_path, streams: streams)
      #
      # Example: Upload by writing records one at a time to the upload stream
      #   job.upload do |writer|
      #     10.times { |i| writer << i }
      #   end
      #
      # Notes:
      # - By default all data read from the file/stream is converted into UTF-8 before being persisted. This
      #   is recommended since Mongo only supports UTF-8 strings.
      # - When zip format, the Zip file/stream must contain only one file, the first file found will be
      #   loaded into the job
      # - If an io stream is supplied, it is read until it returns nil.
      # - Only use this method for UTF-8 data, for binary data use #input_slice or #input_records.
      # - Only call from one thread at a time per job instance.
      # - CSV parsing is slow, so it is left for the workers to do.
      def upload(file_name_or_io = nil, encoding: 'UTF-8', stream_mode: :line, on_first: nil, **args, &block)
        raise(ArgumentError, 'Either file_name_or_io, or a block must be supplied') unless file_name_or_io || block

        block ||= -> (io) do
          iterator = "each_#{stream_mode}".to_sym
          IOStreams.public_send(iterator, file_name_or_io, encoding: encoding, **args) { |line| io << line }
        end

        Writer::Input.collect(self, on_first: on_first, &block)
      end

      # Upload the result of a MongoDB query to the input collection for processing
      # Useful when an entire MongoDB collection, or part thereof needs to be
      # processed by a job.
      #
      # Returns [Integer] the number of records uploaded
      #
      # If a Block is supplied it is passed the document returned from the
      # database and should return a record for processing
      #
      # If no Block is supplied then the record will be the :fields returned
      # from MongoDB
      #
      # Note:
      #   This method uses the collection and not the MongoMapper document to
      #   avoid the overhead of constructing a Model with every document returned
      #   by the query
      #
      # Note:
      #   The Block must return types that can be serialized to BSON.
      #   Valid Types: Hash | Array | String | Integer | Float | Symbol | Regexp | Time
      #   Invalid: Date, etc.
      #
      # Example: Upload document ids
      #   criteria = User.where(state: 'FL')
      #   job.record_count = job.upload_mongo_query(criteria)
      #
      # Example: Upload just the supplied column
      #   criteria = User.where(state: 'FL')
      #   job.record_count = job.upload_mongo_query(criteria, :zip_code)
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

      # Upload results from an Arel into RocketJob::SlicedJob.
      #
      # Params
      #   column_names
      #     When a block is not supplied, supply the names of the columns to be returned
      #     and uploaded into the job
      #     These columns are automatically added to the select list to reduce overhead
      #
      # If a Block is supplied it is passed the model returned from the database and should
      # return the work item to be uploaded into the job.
      #
      # Returns [Integer] the number of records uploaded
      #
      # Example: Upload id's for all users
      #   arel = User.all
      #   job.record_count = job.upload_arel(arel)
      #
      # Example: Upload selected user id's
      #   arel = User.where(country_code: 'US')
      #   job.record_count = job.upload_arel(arel)
      #
      # Example: Upload user_name and zip_code
      #   arel = User.where(country_code: 'US')
      #   job.record_count = job.upload_arel(arel, :user_name, :zip_code)
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

      # Upload sliced range of integer requests as a an arrays of start and end ids
      #
      # Returns [Integer] the number of slices uploaded
      #
      # Uploads one range per slice so that the response can return multiple records
      # for each slice processed
      #
      # Example
      #   job.slice_size = 100
      #   job.record_count = job.upload_integer_range(200, 421)
      #
      #   # Equivalent to calling:
      #   job.record_count = job.insert([200,299])
      #   job.record_count += job.insert([300,399])
      #   job.record_count += job.insert([400,421])
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

      # Upload sliced range of integer requests as an arrays of start and end ids
      # starting with the last range first
      #
      # Returns [Integer] the number of slices uploaded
      #
      # Uploads one range per slice so that the response can return multiple records
      # for each slice processed.
      # Useful for when the highest order integer values should be processed before
      # the lower integer value ranges. For example when processing every record
      # in a database based on the id column
      #
      # Example
      #   job.slice_size = 100
      #   job.record_count = job.upload_integer_range_in_reverse_order(200, 421) * job.slice_size
      #
      #   # Equivalent to calling:
      #   job.insert([400,421])
      #   job.insert([300,399])
      #   job.insert([200,299])
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
          if slice.exception && (record_number = slice.exception.record_number)
            yield(slice.at(record_number - 1), slice)
          end
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

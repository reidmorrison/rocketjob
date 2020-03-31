begin
  require 'active_record'
rescue LoadError
  raise 'RocketJob::Jobs::ReEncrypt::RelationalJob uses ActiveRecord to obtain the database connection, please install the gem "activerecord".'
end

# Batch Worker to Re-encrypt all encrypted fields in MySQL that start with `encrytped_`.
#
# Run in Rails console:
#   RocketJob::Jobs::ReEncrypt::RelationalJob.start
#
# Notes:
# * Uses table names directly since models can be removed over time and the data still needs to be re-encrypted.
# * This job will find any column in the database that starts with`encrypted_`.
# * This means that temporary or other tables not part of the application tables will also be processed.
# * Since it automatically finds and re-encrypts any column, new columns are handled without any manual intervention.
module RocketJob
  module Jobs
    module ReEncrypt
      class RelationalJob < RocketJob::Job
        include RocketJob::Batch

        self.slice_size              = 1000
        self.priority                = 30
        self.destroy_on_complete     = false
        self.compress                = true
        self.throttle_running_jobs   = 1
        self.throttle_running_workers = 10

        # Name of the table being re-encrypted
        field :table_name, type: String

        # Limit the number of records to re-encrypt in test environments
        field :limit, type: Integer

        validates_presence_of :table_name
        before_batch :upload_records

        # Returns [Hash] of table names with each entry being an array
        # of columns that start with encrypted_
        sync_cattr_reader :encrypted_columns do
          h = {}
          connection.tables.each do |table|
            columns = connection.columns(table)
            columns.each do |column|
              if column.name.start_with?('encrypted_')
                add_column = column.name
                (h[table] ||= []) << add_column if add_column
              end
            end
          end
          h
        end

        # Re-encrypt all `encrypted_` columns in the relational database.
        # Queues a Job for each table that needs re-encryption.
        def self.start(**args)
          encrypted_columns.keys.collect do |table|
            create!(table_name: table, description: table, **args)
          end
        end

        # Re-encrypt all encrypted columns for the named table.
        # Does not use AR models since we do not have models for all tables.
        def perform(range)
          start_id, end_id = range

          columns = self.class.encrypted_columns[table_name]
          unless columns&.size&.positive?
            logger.error "No columns for table: #{table_name} from #{start_id} to #{end_id}"
            return
          end

          logger.info "Processing: #{table_name} from #{start_id} to #{end_id}"
          sql = "select id, #{columns.join(',')} from #{quoted_table_name} where id >= #{start_id} and id <= #{end_id}"

          # Use AR to fetch all the records
          self.class.connection.select_rows(sql).each do |row|
            row     = row.unshift(nil)
            index   = 1
            sql     = "update #{quoted_table_name} set "
            updates = []
            columns.collect do |column|
              index += 1
              value = row[index]
              # Prevent re-encryption
              unless value.blank?
                new_value = re_encrypt(value)
                updates << "#{column} = \"#{new_value}\"" if new_value != value
              end
            end
            if updates.size.positive?
              sql << updates.join(', ')
              sql << " where id=#{row[1]}"
              logger.trace sql
              self.class.connection.execute sql
            else
              logger.trace { "Skipping empty values #{table_name}:#{row[1]}" }
            end
          end
        end

        # Returns a database connection.
        #
        # Override this method to support other ways of obtaining a thread specific database connection.
        def self.connection
          ActiveRecord::Base.connection
        end

        private

        def quoted_table_name
          @quoted_table_name ||= self.class.connection.quote_table_name(table_name)
        end

        def re_encrypt(encrypted_value)
          return encrypted_value if (encrypted_value == '') || encrypted_value.nil?
          SymmetricEncryption.encrypt(SymmetricEncryption.decrypt(encrypted_value))
        end

        # Upload range to re-encrypt all rows in the specified table.
        def upload_records
          start_id          = self.class.connection.select_value("select min(id) from #{quoted_table_name}").to_i
          last_id           = self.class.connection.select_value("select max(id) from #{quoted_table_name}").to_i
          self.record_count = last_id.positive? ? (input.upload_integer_range_in_reverse_order(start_id, last_id) * slice_size) : 0
        end
      end
    end
  end
end

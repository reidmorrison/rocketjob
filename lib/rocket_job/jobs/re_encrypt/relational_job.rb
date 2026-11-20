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
if defined?(ActiveRecord) && defined?(SyncAttr)
  require "active_record"
  require "sync_attr"

  module RocketJob
    module Jobs
      module ReEncrypt
        class RelationalJob < RocketJob::Job
          include RocketJob::Batch

          self.priority                 = 30
          self.destroy_on_complete      = false
          self.throttle_running_jobs    = 1
          self.throttle_running_workers = 10

          input_category slice_size: 1_000
          input_contract RocketJob::Batch::RangeContract

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
                if column.name.start_with?("encrypted_")
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
            start_id = range.first_id
            end_id   = range.last_id

            columns = self.class.encrypted_columns[table_name]
            unless columns&.size&.positive?
              logger.error "No columns for table: #{table_name} from #{start_id} to #{end_id}"
              return
            end

            logger.info "Processing: #{table_name} from #{start_id} to #{end_id}"
            connection = self.class.connection
            selected   = columns.map { |column| connection.quote_column_name(column) }.join(", ")
            sql        = "select id, #{selected} from #{quoted_table_name} where id >= #{start_id} and id <= #{end_id}"

            # Use AR to fetch all the records, whose rows Active Record may freeze.
            connection.select_rows(sql).each do |id, *values|
              updates = columns.zip(values).filter_map do |column, value|
                # Skip blank values, which are not encrypted.
                next if value.blank?

                new_value = re_encrypt(value)
                "#{connection.quote_column_name(column)} = #{connection.quote(new_value)}" if new_value != value
              end
              if updates.empty?
                logger.trace { "Skipping empty values #{table_name}:#{id}" }
              else
                update = "update #{quoted_table_name} set #{updates.join(', ')} where id=#{connection.quote(id)}"
                logger.trace { update }
                connection.execute update
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
            return encrypted_value if (encrypted_value == "") || encrypted_value.nil?

            SymmetricEncryption.encrypt(SymmetricEncryption.decrypt(encrypted_value))
          end

          # Upload the range of ids of all rows in the specified table, highest ids first, one range per slice, see
          # RocketJob::Batch::RangeContract, which also counts each id as a record.
          def upload_records
            start_id = self.class.connection.select_value("select min(id) from #{quoted_table_name}").to_i
            last_id  = self.class.connection.select_value("select max(id) from #{quoted_table_name}").to_i
            return self.record_count = 0 unless last_id.positive?

            upload(last_id..start_id)
          end
        end
      end
    end
  end
end

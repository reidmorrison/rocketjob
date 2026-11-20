require_relative "../../test_helper"
require "active_record"
require "sync_attr"

ActiveRecord::Base.configurations = YAML.safe_load(ERB.new(File.read("test/config/database.yml")).result)
ActiveRecord::Base.establish_connection(:test)

ActiveRecord::Schema.define version: 0 do
  create_table :relational_job_users, force: true do |t|
    t.string :encrypted_name
  end

  create_table :relational_job_empties, force: true do |t|
    t.string :encrypted_name
  end
end

module Jobs
  module ReEncrypt
    class RelationalJobTest < Minitest::Test
      # Keeps the range of ids that #perform receives, to check them.
      class RangesJob < RocketJob::Jobs::ReEncrypt::RelationalJob
        input_category slice_size: 2

        output_category

        def perform(range)
          super
          range
        end
      end

      describe RocketJob::Jobs::ReEncrypt::RelationalJob do
        let(:connection) { ActiveRecord::Base.connection }
        let(:names) { %w[one two three four five] }

        before do
          # The encrypted columns of each table are found once, and kept, so that a table created after they were read
          # would be missing: find them again.
          [RocketJob::Jobs::ReEncrypt::RelationalJob, RangesJob].each do |job_class|
            next unless job_class.class_variables(false).include?(:@@encrypted_columns)

            job_class.remove_class_variable(:@@encrypted_columns)
          end
          RangesJob.delete_all
          connection.execute("delete from relational_job_users")
          names.each_with_index do |name, index|
            encrypted = SymmetricEncryption.encrypt(name, random_iv: true)
            connection.execute("insert into relational_job_users (id, encrypted_name) values (#{index + 1}, '#{encrypted}')")
          end
        end

        it "re-encrypts every row, one range of ids per slice, highest ids first" do
          job = RangesJob.create!(table_name: "relational_job_users")
          job.perform_now

          assert_predicate job, :completed?, -> { job.input.failed.first&.exception&.message }
          assert_equal [[4, 5], [2, 3], [1, 1]], job.output.flat_map(&:to_a)

          values = connection.select_rows("select encrypted_name from relational_job_users order by id").flatten

          # Encrypted again with the current key, without the random IV that each value was encrypted with.
          expected = names.map { |name| SymmetricEncryption.encrypt(name) }

          assert_equal expected, values
        ensure
          job&.cleanup!
        end

        it "uploads nothing for an empty table" do
          job = RangesJob.create!(table_name: "relational_job_empties")
          job.perform_now

          assert_predicate job, :completed?
          assert_equal 0, job.record_count
        ensure
          job&.cleanup!
        end
      end
    end
  end
end

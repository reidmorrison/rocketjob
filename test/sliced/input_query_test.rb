require_relative "../test_helper"
require "active_record"

ActiveRecord::Base.configurations = YAML.safe_load(ERB.new(File.read("test/config/database.yml")).result)
ActiveRecord::Base.establish_connection(:test)

ActiveRecord::Schema.define version: 0 do
  create_table :input_query_people, force: true do |t|
    t.string :name
    t.integer :age
    t.date :born_on
  end

  create_table :input_query_pets, force: true do |t|
    t.integer :input_query_person_id
    t.string :name
  end

  create_table :input_query_codes, id: false, force: true do |t|
    t.string :code, primary_key: true
    t.string :name
    t.binary :data
  end

  create_table :input_query_events, id: false, force: true do |t|
    t.string :name
  end
end

# ActiveRecord source for upload_query.
class InputQueryPerson < ActiveRecord::Base
  has_many :input_query_pets
  alias_attribute :full_name, :name
end

class InputQueryPet < ActiveRecord::Base
end

# A model whose reader returns another value than its column holds.
class InputQueryShoutingPerson < ActiveRecord::Base
  self.table_name = "input_query_people"

  def name
    super&.upcase
  end
end

# A model whose primary key is not id.
class InputQueryCode < ActiveRecord::Base
  self.primary_key = "code"
end

# A model without a primary key.
class InputQueryEvent < ActiveRecord::Base
end

# Mongoid source for upload_mongo_query.
class InputQueryDoc
  include Mongoid::Document

  store_in collection: "input_query_docs"

  field :name, type: String
  field :age, type: Integer
end

# Whether IOStreams streams a query on the test database. It cannot on JRuby, whose SQLite adapter is not the sqlite3
# gem, where a relation raises ArgumentError, and only its batches can be uploaded.
QUERY_STREAMS =
  begin
    IOStreams.stream(InputQueryPerson.limit(0)).each(:array) { nil }
    true
  rescue ArgumentError
    false
  end

# Why a test of a streamed query is skipped, see QUERY_STREAMS.
QUERY_STREAMS_SKIP = "IOStreams cannot stream a query on this database, such as SQLite on JRuby".freeze

module Sliced
  class InputQueryTest < Minitest::Test
    class QueryUploadJob < RocketJob::Job
      include RocketJob::Batch

      def perform(record)
        record
      end
    end

    # A job whose input category has a schema of its own.
    class QueryUploadSchemaJob < RocketJob::Job
      include RocketJob::Batch

      input_category schema: {
        "fields" => [
          {"name" => "name", "type" => "string"},
          {"name" => "age", "type" => "number"}
        ]
      }

      def perform(record)
        record
      end
    end

    # Returns [Array] the records of the supplied job, as `#perform` receives them, see
    # RocketJob::Category::Input#parse_records.
    def self.performed_records(job)
      records = []
      job.input.each do |slice|
        job.input_category.parse_records(slice.records) { |record| records << record }
      end
      records
    end

    # Removes the rows and documents that the tests created.
    def self.delete_all
      [InputQueryPerson, InputQueryPet, InputQueryCode, InputQueryEvent].each(&:delete_all)
      InputQueryDoc.delete_all
    end

    describe RocketJob::Sliced::Input do
      let(:collection_name) { :"rocket_job.slices.query_test" }

      let :input do
        RocketJob::Sliced::Input.new(collection_name: collection_name, slice_size: 100)
      end

      # Uploads the records of the supplied relation, or its batches, see RocketJob::Sliced::Input#upload_query.
      def upload_query(query, columns: nil, &)
        input.upload_query(RocketJob::Sliced::QueryUpload.new(query, columns: columns), &)
      end

      before do
        input.delete_all
      end

      after do
        input.drop
        InputQueryTest.delete_all
      end

      describe "#upload_query" do
        # Whether the tests read the batches of a relation, which any database reads, rather than a streamed query.
        def batches?
          false
        end

        before do
          skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS || batches?
          @alice = InputQueryPerson.create!(name: "Alice", age: 30)
          @bob   = InputQueryPerson.create!(name: "Bob", age: 40)
        end

        it "uploads the id of each record by default" do
          count = upload_query(InputQueryPerson.all)

          assert_equal 2, count
          assert_equal [@alice.id, @bob.id].sort, input.collect(&:to_a).flatten.sort
        end

        it "uploads a single named column" do
          count = upload_query(InputQueryPerson.all, columns: [:name])

          assert_equal 2, count
          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "raises for several columns, whose rows are uploaded in slices into an input category" do
          assert_raises(ArgumentError) { upload_query(InputQueryPerson.all, columns: %i[name age]) }
          assert_equal 0, input.count
        end

        it "uploads what the block returns for each row" do
          upload_query(InputQueryPerson.all) { |row| row["name"].upcase }

          assert_equal %w[ALICE BOB], input.collect(&:to_a).flatten.sort
        end

        it "yields each row to the block as a Hash of the columns that the relation selects, by name" do
          rows = []
          upload_query(InputQueryPerson.select(:name, :age).order(:age)) do |row|
            rows << row
            row["name"]
          end

          assert_equal [{"name" => "Alice", "age" => 30}, {"name" => "Bob", "age" => 40}], rows
        end

        it "yields every column of the table when the relation selects none" do
          rows = []
          upload_query(InputQueryPerson.where(name: "Alice")) { |row| rows << row }

          assert_equal [{"id" => @alice.id, "name" => "Alice", "age" => 30, "born_on" => nil}], rows
        end

        it "yields only the named columns to the block" do
          rows = []
          upload_query(InputQueryPerson.order(:age), columns: %i[name age]) { |row| rows << row }

          assert_equal [{"name" => "Alice", "age" => 30}, {"name" => "Bob", "age" => 40}], rows
        end

        it "yields the rows of a model without a primary key to the block" do
          InputQueryEvent.create!(name: "start")
          upload_count = upload_query(InputQueryEvent.all) { |row| row["name"] }

          assert_equal 1, upload_count
          assert_equal %w[start], input.collect(&:to_a).flatten
        end

        it "yields the rows to the block in the order of the relation" do
          upload_query(InputQueryPerson.order(age: :desc)) { |row| row["name"] }

          assert_equal %w[Bob Alice], input.collect(&:to_a).flatten
        end

        it "raises for a relation that loads associations, also with a block" do
          assert_raises(ArgumentError) do
            upload_query(InputQueryPerson.preload(:input_query_pets)) { |row| row["name"] }
          end
          assert_equal 0, input.count
        end

        it "uploads the rows in the order of the relation" do
          upload_query(InputQueryPerson.order(age: :desc), columns: [:name])

          assert_equal %w[Bob Alice], input.collect(&:to_a).flatten
        end

        it "uploads the rows within the limit of a sorted relation" do
          count = upload_query(InputQueryPerson.order(age: :desc).limit(1), columns: [:name])

          assert_equal 1, count
          assert_equal %w[Bob], input.collect(&:to_a).flatten
        end

        it "uploads the values that the columns hold, rather than what a reader of the model returns" do
          upload_query(InputQueryShoutingPerson.all, columns: [:name])

          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "uploads only the columns that it names, rather than those that the relation selects" do
          upload_query(InputQueryPerson.select(:id, :name), columns: [:age])

          assert_equal [30, 40], input.collect(&:to_a).flatten.sort
        end

        it "uploads the primary key of a model whose primary key is not id" do
          InputQueryCode.create!(code: "a1", name: "Alice")
          InputQueryCode.create!(code: "b2", name: "Bob")

          assert_equal 2, upload_query(InputQueryCode.all)
          assert_equal %w[a1 b2], input.collect(&:to_a).flatten.sort
        end

        it "raises for a model without a primary key, unless the columns are named" do
          InputQueryEvent.create!(name: "start")
          error = assert_raises(ArgumentError) { upload_query(InputQueryEvent.all) }

          assert_equal "InputQueryEvent has no primary key, so name the columns to upload with `columns:`", error.message
          assert_equal 1, upload_query(InputQueryEvent.all, columns: [:name])
          assert_equal %w[start], input.collect(&:to_a).flatten
        end

        it "uploads only the rows that were committed, since it reads them on a connection of its own" do
          uploaded = nil
          InputQueryPerson.transaction do
            InputQueryPerson.create!(name: "Carol", age: 50)
            uploaded = upload_query(InputQueryPerson.all, columns: [:name])
            raise(ActiveRecord::Rollback)
          end

          assert_equal 2, uploaded
          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "raises for a relation that loads associations, and uploads nothing" do
          error = assert_raises(ArgumentError) { upload_query(InputQueryPerson.includes(:input_query_pets)) }

          assert_includes error.message, "includes cannot be read as rows"
          assert_equal 0, input.count
        end

        describe "the batches of a relation" do
          def batches?
            true
          end

          it "uploads the primary key of each row" do
            assert_equal 2, upload_query(InputQueryPerson.in_batches(of: 1))
            assert_equal [@alice.id, @bob.id], input.collect(&:to_a).flatten.sort
          end

          it "uploads the columns that the relation selects before in_batches" do
            upload_query(InputQueryPerson.select(:id, :age).in_batches(of: 1), columns: [:age])

            assert_equal [30, 40], input.collect(&:to_a).flatten.sort
          end

          it "finds a column by the name of the attribute that aliases it" do
            upload_query(InputQueryPerson.in_batches(of: 1), columns: [:full_name])

            assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
          end

          it "raises before any batch is read for a column that the relation does not select" do
            error = assert_raises(ArgumentError) do
              upload_query(InputQueryPerson.select(:id).in_batches(of: 1), columns: [:name])
            end

            assert_equal "The batches of the InputQueryPerson query do not select the column name, which is " \
                         "read: select it before `in_batches`, or upload the relation instead", error.message
            assert_equal 0, input.count
          end

          it "uploads the rows that an open transaction of the caller wrote, since it reads on that connection" do
            InputQueryPerson.transaction do
              InputQueryPerson.create!(name: "Carol", age: 50)
              upload_query(InputQueryPerson.in_batches(of: 1), columns: [:name])
              raise(ActiveRecord::Rollback)
            end

            assert_equal %w[Alice Bob Carol], input.collect(&:to_a).flatten.sort
          end

          it "uploads what the block returns for each row" do
            upload_query(InputQueryPerson.in_batches(of: 1)) { |row| row["name"].upcase }

            assert_equal %w[ALICE BOB], input.collect(&:to_a).flatten.sort
          end

          it "yields only the named columns of each row to the block" do
            rows = []
            upload_query(InputQueryPerson.in_batches(of: 1), columns: %i[full_name age]) { |row| rows << row }

            expected = [{"name" => "Alice", "age" => 30}, {"name" => "Bob", "age" => 40}]

            assert_equal(expected, rows.sort_by { |row| row["age"] })
          end
        end
      end

      describe "#upload_mongo_query" do
        before do
          @alice = InputQueryDoc.create!(name: "Alice", age: 30)
          @bob   = InputQueryDoc.create!(name: "Bob", age: 40)
        end

        it "uploads the _id of each document by default" do
          count = input.upload_mongo_query(InputQueryDoc.all)

          assert_equal 2, count
          assert_equal [@alice.id, @bob.id].sort, input.collect(&:to_a).flatten.sort
        end

        it "uploads a single named column" do
          input.upload_mongo_query(InputQueryDoc.all, columns: [:name])

          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "uploads several columns as a Hash of the fields by name" do
          input.upload_mongo_query(InputQueryDoc.all, columns: %i[name age])
          records = input.collect(&:to_a).flatten(1).sort_by { |record| record["age"] }

          assert_equal [{"name" => "Alice", "age" => 30}, {"name" => "Bob", "age" => 40}], records
        end

        it "honors a supplied block" do
          input.upload_mongo_query(InputQueryDoc.all) { |document| document["name"].downcase }

          assert_equal %w[alice bob], input.collect(&:to_a).flatten.sort
        end
      end
    end

    describe RocketJob::Sliced::QueryUpload do
      after do
        InputQueryTest.delete_all
      end

      before do
        InputQueryPerson.create!(name: "Alice", age: 30, born_on: Date.new(1990, 2, 3))
        InputQueryPerson.create!(name: "Bob", age: 40)
      end

      # Returns [Array<IOStreams::Slice>] the slices of the supplied query.
      def slices(query, columns:, size: 10)
        slices = []
        RocketJob::Sliced::QueryUpload.new(query, columns: columns).each_slice(size: size) { |slice| slices << slice }
        slices
      end

      it "reads the slices of the rows of the columns, whose header row names them, and whose rows are records" do
        skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

        slice = slices(InputQueryPerson.order(:age), columns: %i[name age]).first

        assert_equal %w[name age], slice.header
        assert_equal [["Alice", 30], ["Bob", 40]], slice.to_a
        refute_predicate slice, :blank_rows?
      end

      it "reads slices of up to the supplied number of rows" do
        skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

        assert_equal [1, 1], slices(InputQueryPerson.order(:age), columns: %i[name age], size: 1).collect(&:size)
      end

      it "narrows the slices of the batches of a relation to the columns, found by their names" do
        slice = slices(InputQueryPerson.in_batches(of: 10), columns: %i[full_name age]).first

        assert_equal %w[name age], slice.header
        assert_equal [["Alice", 30], ["Bob", 40]], slice.sort_by(&:last)
        refute_predicate slice, :blank_rows?
      end

      it "describes the columns by their names, and their schema by their types, with String keys" do
        query = RocketJob::Sliced::QueryUpload.new(InputQueryPerson.all, columns: %i[full_name born_on])

        assert_equal %w[name born_on], query.column_names
        assert_equal({"fields" => [{"name" => "name", "type" => "string"}, {"name" => "born_on", "type" => "date"}]},
                     query.schema)
      end

      it "describes only the columns of the batches of a relation that are read" do
        query = RocketJob::Sliced::QueryUpload.new(InputQueryPerson.in_batches(of: 10), columns: %i[born_on name])

        assert_equal %w[born_on name], query.column_names
        assert_equal({"fields" => [{"name" => "born_on", "type" => "date"}, {"name" => "name", "type" => "string"}]},
                     query.schema)
      end

      it "checks the columns against a schema, and raises for columns that do not match its fields" do
        schema = {"fields" => [{"name" => "name", "type" => "string"}, {"name" => "age", "type" => "number"}]}

        RocketJob::Sliced::QueryUpload.new(InputQueryPerson.all, columns: %i[full_name age]).check_schema(schema)
        assert_raises(IOStreams::Errors::InvalidHeader) do
          RocketJob::Sliced::QueryUpload.new(InputQueryPerson.all, columns: %i[name born_on]).check_schema(schema)
        end
      end

      it "checks the columns that the batches of a relation are narrowed to against a schema" do
        schema = {"fields" => [{"name" => "name", "type" => "string"}, {"name" => "age", "type" => "number"}]}

        batches = InputQueryPerson.in_batches(of: 1)
        RocketJob::Sliced::QueryUpload.new(batches, columns: %i[name age]).check_schema(schema)
        assert_raises(IOStreams::Errors::InvalidHeader) do
          RocketJob::Sliced::QueryUpload.new(batches, columns: %i[name born_on]).check_schema(schema)
        end
      end

      it "uploads one column as its value, and several in slices" do
        assert_predicate RocketJob::Sliced::QueryUpload.new(InputQueryPerson.all), :single_column?
        refute_predicate RocketJob::Sliced::QueryUpload.new(InputQueryPerson.all, columns: %i[name age]), :single_column?
      end
    end

    describe "RocketJob::Batch#upload of a query" do
      let(:job) { QueryUploadJob.new }
      let(:schema_job) { QueryUploadSchemaJob.new }

      before do
        InputQueryPerson.create!(name: "Alice", age: 30, born_on: Date.new(1990, 2, 3))
        InputQueryPerson.create!(name: "Bob", age: 40)
        InputQueryDoc.create!(name: "Alice", age: 30)
        InputQueryDoc.create!(name: "Bob", age: 40)
      end

      after do
        job.cleanup!
        schema_job.cleanup!
        InputQueryTest.delete_all
      end

      it "uploads several columns of an Active Record relation, which perform receives as a Hash of their types" do
        skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

        assert_equal 2, job.upload(InputQueryPerson.order(:age), columns: %i[name born_on])
        assert_equal 2, job.record_count

        records = InputQueryTest.performed_records(job)

        assert_equal [{"name" => "Alice", "born_on" => Date.new(1990, 2, 3)}, {"name" => "Bob", "born_on" => nil}],
                     records
        assert_instance_of Date, records.first["born_on"]
      end

      it "keeps the schema of the columns in the input category, and records that an upload set it" do
        skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

        job.upload(InputQueryPerson.all, columns: %i[name born_on])

        assert_equal({"fields" => [{"name" => "name", "type" => "string"}, {"name" => "born_on", "type" => "date"}]},
                     job.input_category.schema)
        assert_predicate job.input_category, :schema_uploaded?
      end

      it "uploads a row whose every value is null as a record" do
        skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

        InputQueryPerson.create!(name: nil, age: 50)
        job.upload(InputQueryPerson.where(age: 50), columns: %i[name born_on])

        assert_equal [{"name" => nil, "born_on" => nil}], InputQueryTest.performed_records(job)
      end

      it "narrows the batches of a relation to the columns" do
        job.upload(InputQueryPerson.in_batches(of: 1), columns: %i[full_name age])

        records = InputQueryTest.performed_records(job).sort_by { |record| record["age"] }

        assert_equal [{"name" => "Alice", "age" => 30}, {"name" => "Bob", "age" => 40}], records
      end

      it "reads a second upload by the schema that the first kept, and raises for other columns" do
        skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

        job.upload(InputQueryPerson.all, columns: %i[name age])

        assert_equal 2, job.upload(InputQueryPerson.all, columns: %i[name age])
        assert_raises(IOStreams::Errors::InvalidHeader) { job.upload(InputQueryPerson.all, columns: %i[name born_on]) }
        assert_equal 4, job.record_count
        assert_equal 4, job.input.collect(&:size).sum
      end

      it "reads the rows by the schema of the input category, which it keeps" do
        skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

        schema_job.upload(InputQueryPerson.order(:age), columns: %i[name age])

        assert_equal [{"name" => "Alice", "age" => 30}, {"name" => "Bob", "age" => 40}],
                     InputQueryTest.performed_records(schema_job)
        assert_instance_of BigDecimal, InputQueryTest.performed_records(schema_job).first["age"]
        refute_predicate schema_job.input_category, :schema_uploaded?
      end

      it "raises before any row is read for columns that do not match the schema of the input category" do
        assert_raises(IOStreams::Errors::InvalidHeader) do
          schema_job.upload(InputQueryPerson.all, columns: %i[name born_on])
        end
        assert_equal 0, schema_job.input.count
      end

      it "raises before any batch is read for columns of the batches that do not match the schema" do
        assert_raises(IOStreams::Errors::InvalidHeader) do
          schema_job.upload(InputQueryPerson.in_batches(of: 1), columns: %i[name born_on])
        end
        assert_equal 0, schema_job.input.count
      end

      it "restores the input category when the upload fails, so that it can upload again" do
        skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

        InputQueryCode.create!(code: "a1", name: "Alice", data: "\xFF".b)

        assert_raises(EncodingError) { job.upload(InputQueryCode.all, columns: %i[name data]) }
        assert_nil job.input_category.schema
        refute_predicate job.input_category, :schema_uploaded?
        assert_equal 0, job.input.count
      end

      it "does not keep a schema that an upload read in the next run of a restarted job" do
        skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

        job.upload(InputQueryPerson.all, columns: %i[name age])
        copy = job.input_category.restart_copy

        assert_nil copy.schema
        refute_predicate copy, :schema_uploaded?
      end

      it "keeps the schema that the application set in the next run of a restarted job" do
        copy = QueryUploadSchemaJob.new.input_category.restart_copy

        assert_equal "age", copy.schema["fields"].last["name"]
      end

      it "uploads what the block returns for each row of an Active Record relation" do
        skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

        assert_equal(2, job.upload(InputQueryPerson.all) { |row| row["name"].upcase })
        assert_equal 2, job.record_count
        assert_equal %w[ALICE BOB], job.input.collect(&:to_a).flatten.sort
      end

      it "uploads the columns of the batches of an Active Record relation" do
        assert_equal 2, job.upload(InputQueryPerson.select(:name).in_batches(of: 1), columns: [:name])
        assert_equal 2, job.record_count
        assert_equal %w[Alice Bob], job.input.collect(&:to_a).flatten.sort
      end

      it "uploads several fields of a Mongoid query, which perform receives as a Hash" do
        job.upload(InputQueryDoc.all, columns: %i[name age])
        records = InputQueryTest.performed_records(job).sort_by { |record| record["age"] }

        assert_equal [{"name" => "Alice", "age" => 30}, {"name" => "Bob", "age" => 40}], records
      end

      it "uploads what the block returns for each document of a Mongoid query" do
        assert_equal(2, job.upload(InputQueryDoc.all) { |document| document["name"].downcase })
        assert_equal %w[alice bob], job.input.collect(&:to_a).flatten.sort
      end

      it "rejects a file option for a query" do
        error = assert_raises(ArgumentError) { job.upload(InputQueryDoc.all, file_name: "x.csv") }

        assert_equal "Unknown keyword arguments when uploading a Mongoid::Criteria. " \
                     "Only accepts :category, :columns, or :slice_batch_size", error.message
      end
    end
  end
end

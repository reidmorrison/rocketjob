require_relative "../test_helper"
require "active_record"

ActiveRecord::Base.configurations = YAML.safe_load(ERB.new(File.read("test/config/database.yml")).result)
ActiveRecord::Base.establish_connection(:test)

ActiveRecord::Schema.define version: 0 do
  create_table :input_query_people, force: true do |t|
    t.string :name
    t.integer :age
  end

  create_table :input_query_pets, force: true do |t|
    t.integer :input_query_person_id
    t.string :name
  end

  create_table :input_query_codes, id: false, force: true do |t|
    t.string :code, primary_key: true
    t.string :name
  end

  create_table :input_query_events, id: false, force: true do |t|
    t.string :name
  end
end

# ActiveRecord source for upload_arel.
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

    describe RocketJob::Sliced::Input do
      let(:collection_name) { :"rocket_job.slices.query_test" }

      let :input do
        RocketJob::Sliced::Input.new(collection_name: collection_name, slice_size: 100)
      end

      before do
        input.delete_all
        InputQueryPerson.delete_all
        InputQueryDoc.delete_all
      end

      after do
        input.drop
        [InputQueryPerson, InputQueryPet, InputQueryCode, InputQueryEvent].each(&:delete_all)
        InputQueryDoc.delete_all
      end

      describe "#upload_arel" do
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
          count = input.upload_arel(InputQueryPerson.all)

          assert_equal 2, count
          assert_equal [@alice.id, @bob.id].sort, input.collect(&:to_a).flatten.sort
        end

        it "uploads a single named column" do
          count = input.upload_arel(InputQueryPerson.all, columns: [:name])

          assert_equal 2, count
          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "uploads multiple columns as arrays" do
          input.upload_arel(InputQueryPerson.all, columns: %i[name age])
          rows = input.collect(&:to_a).flatten(1).sort

          assert_equal [["Alice", 30], ["Bob", 40]], rows
        end

        it "uploads what the block returns for each row" do
          input.upload_arel(InputQueryPerson.all) { |row| row["name"].upcase }

          assert_equal %w[ALICE BOB], input.collect(&:to_a).flatten.sort
        end

        it "yields each row to the block as a Hash of the columns that the relation selects, by name" do
          rows = []
          input.upload_arel(InputQueryPerson.select(:name, :age).order(:age)) do |row|
            rows << row
            row["name"]
          end

          assert_equal [{"name" => "Alice", "age" => 30}, {"name" => "Bob", "age" => 40}], rows
        end

        it "yields every column of the table when the relation selects none" do
          rows = []
          input.upload_arel(InputQueryPerson.where(name: "Alice")) { |row| rows << row }

          assert_equal [{"id" => @alice.id, "name" => "Alice", "age" => 30}], rows
        end

        it "yields only the named columns to the block" do
          rows = []
          input.upload_arel(InputQueryPerson.order(:age), columns: [:name]) { |row| rows << row }

          assert_equal [{"name" => "Alice"}, {"name" => "Bob"}], rows
        end

        it "yields the rows to the block in the order of the relation" do
          input.upload_arel(InputQueryPerson.order(age: :desc)) { |row| row["name"] }

          assert_equal %w[Bob Alice], input.collect(&:to_a).flatten
        end

        it "raises for a relation that loads associations, also with a block" do
          assert_raises(ArgumentError) do
            input.upload_arel(InputQueryPerson.preload(:input_query_pets)) { |row| row["name"] }
          end
          assert_equal 0, input.count
        end

        it "uploads the rows in the order of the relation" do
          input.upload_arel(InputQueryPerson.order(age: :desc), columns: [:name])

          assert_equal %w[Bob Alice], input.collect(&:to_a).flatten
        end

        it "uploads the rows within the limit of a sorted relation" do
          count = input.upload_arel(InputQueryPerson.order(age: :desc).limit(1), columns: [:name])

          assert_equal 1, count
          assert_equal %w[Bob], input.collect(&:to_a).flatten
        end

        it "uploads the values that the columns hold, rather than what a reader of the model returns" do
          input.upload_arel(InputQueryShoutingPerson.all, columns: [:name])

          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "uploads only the columns that it names, rather than those that the relation selects" do
          input.upload_arel(InputQueryPerson.select(:id, :name), columns: [:age])

          assert_equal [30, 40], input.collect(&:to_a).flatten.sort
        end

        it "uploads the primary key of a model whose primary key is not id" do
          InputQueryCode.create!(code: "a1", name: "Alice")
          InputQueryCode.create!(code: "b2", name: "Bob")

          assert_equal 2, input.upload_arel(InputQueryCode.all)
          assert_equal %w[a1 b2], input.collect(&:to_a).flatten.sort
        end

        it "raises for a model without a primary key, unless the columns are named" do
          InputQueryEvent.create!(name: "start")
          error = assert_raises(ArgumentError) { input.upload_arel(InputQueryEvent.all) }

          assert_equal "InputQueryEvent has no primary key, so name the columns to upload with `columns:`", error.message
          assert_equal 1, input.upload_arel(InputQueryEvent.all, columns: [:name])
          assert_equal %w[start], input.collect(&:to_a).flatten
        end

        it "uploads only the rows that were committed, since it reads them on a connection of its own" do
          uploaded = nil
          InputQueryPerson.transaction do
            InputQueryPerson.create!(name: "Carol", age: 50)
            uploaded = input.upload_arel(InputQueryPerson.all, columns: [:name])
            raise(ActiveRecord::Rollback)
          end

          assert_equal 2, uploaded
          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        describe "the batches of a relation" do
          def batches?
            true
          end

          it "uploads the primary key of each row" do
            assert_equal 2, input.upload_arel(InputQueryPerson.in_batches(of: 1))
            assert_equal [@alice.id, @bob.id], input.collect(&:to_a).flatten.sort
          end

          it "uploads the named columns of each row, as arrays" do
            input.upload_arel(InputQueryPerson.in_batches(of: 1), columns: %i[name age])

            assert_equal [["Alice", 30], ["Bob", 40]], input.collect(&:to_a).flatten(1).sort
          end

          it "uploads the columns that the relation selects before in_batches" do
            input.upload_arel(InputQueryPerson.select(:id, :age).in_batches(of: 1), columns: [:age])

            assert_equal [30, 40], input.collect(&:to_a).flatten.sort
          end

          it "finds a column by the name of the attribute that aliases it" do
            input.upload_arel(InputQueryPerson.in_batches(of: 1), columns: [:full_name])

            assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
          end

          it "raises before any batch is read for a column that the relation does not select" do
            error = assert_raises(ArgumentError) do
              input.upload_arel(InputQueryPerson.select(:id).in_batches(of: 1), columns: [:name])
            end

            assert_equal "The batches of the InputQueryPerson query do not select the column name, which is " \
                         "read: select it before `in_batches`, or upload the relation instead", error.message
            assert_equal 0, input.count
          end

          it "uploads the rows that an open transaction of the caller wrote, since it reads on that connection" do
            InputQueryPerson.transaction do
              InputQueryPerson.create!(name: "Carol", age: 50)
              input.upload_arel(InputQueryPerson.in_batches(of: 1), columns: [:name])
              raise(ActiveRecord::Rollback)
            end

            assert_equal %w[Alice Bob Carol], input.collect(&:to_a).flatten.sort
          end

          it "uploads what the block returns for each row" do
            input.upload_arel(InputQueryPerson.in_batches(of: 1)) { |row| row["name"].upcase }

            assert_equal %w[ALICE BOB], input.collect(&:to_a).flatten.sort
          end

          it "yields only the named columns of each row to the block" do
            rows = []
            input.upload_arel(InputQueryPerson.in_batches(of: 1), columns: %i[full_name age]) { |row| rows << row }

            expected = [{"name" => "Alice", "age" => 30}, {"name" => "Bob", "age" => 40}]

            assert_equal(expected, rows.sort_by { |row| row["age"] })
          end
        end

        it "raises for a relation that loads associations, and uploads nothing" do
          error = assert_raises(ArgumentError) { input.upload_arel(InputQueryPerson.includes(:input_query_pets)) }

          assert_includes error.message, "includes cannot be read as rows"
          assert_equal 0, input.count
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

        it "uploads multiple columns as arrays" do
          input.upload_mongo_query(InputQueryDoc.all, columns: %i[name age])
          rows = input.collect(&:to_a).flatten(1).sort

          assert_equal [["Alice", 30], ["Bob", 40]], rows
        end

        it "honors a supplied block" do
          input.upload_mongo_query(InputQueryDoc.all) { |document| document["name"].downcase }

          assert_equal %w[alice bob], input.collect(&:to_a).flatten.sort
        end
      end
    end

    describe "RocketJob::Batch#upload of a query" do
      let(:job) { QueryUploadJob.new }

      before do
        InputQueryPerson.delete_all
        InputQueryDoc.delete_all
        InputQueryPerson.create!(name: "Alice", age: 30)
        InputQueryPerson.create!(name: "Bob", age: 40)
        InputQueryDoc.create!(name: "Alice", age: 30)
        InputQueryDoc.create!(name: "Bob", age: 40)
      end

      after do
        job.cleanup!
        InputQueryPerson.delete_all
        InputQueryDoc.delete_all
      end

      it "uploads the columns of an Active Record relation" do
        skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

        assert_equal 2, job.upload(InputQueryPerson.all, columns: %i[name age])
        assert_equal 2, job.record_count
        assert_equal [["Alice", 30], ["Bob", 40]], job.input.collect(&:to_a).flatten(1).sort
      end

      it "uploads what the block returns for each row of an Active Record relation" do
        assert_equal(2, job.upload(InputQueryPerson.all) { |row| row["name"].upcase })
        assert_equal 2, job.record_count
        assert_equal %w[ALICE BOB], job.input.collect(&:to_a).flatten.sort
      end

      it "uploads the columns of the batches of an Active Record relation" do
        assert_equal 2, job.upload(InputQueryPerson.select(:name).in_batches(of: 1), columns: [:name])
        assert_equal 2, job.record_count
        assert_equal %w[Alice Bob], job.input.collect(&:to_a).flatten.sort
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

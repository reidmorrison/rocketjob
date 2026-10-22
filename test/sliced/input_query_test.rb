require_relative "../test_helper"
require "active_record"

ActiveRecord::Base.configurations = YAML.safe_load(ERB.new(File.read("test/config/database.yml")).result)
ActiveRecord::Base.establish_connection(:test)

ActiveRecord::Schema.define version: 0 do
  create_table :input_query_people, force: true do |t|
    t.string :name
    t.integer :age
  end
end

# ActiveRecord source for upload_arel.
class InputQueryPerson < ActiveRecord::Base
end

# Whether IOStreams streams a query on the test database. It cannot on JRuby, whose SQLite adapter is not the sqlite3
# gem, where a relation raises ArgumentError, and only its batches can be uploaded. Any other error is raised, so that
# the tests of a streamed query fail rather than skip.
QUERY_STREAMS =
  begin
    IOStreams.stream(InputQueryPerson.limit(0)).each(:array) { nil }
    true
  rescue ArgumentError => e
    raise unless e.message.start_with?("IOStreams cannot stream a query on ")

    false
  end

# Why a test of a streamed query is skipped, see QUERY_STREAMS.
QUERY_STREAMS_SKIP = "IOStreams cannot stream a query on this database, such as SQLite on JRuby".freeze

# Mongoid source for upload_mongo_query.
class InputQueryDoc
  include Mongoid::Document

  store_in collection: "input_query_docs"

  field :name, type: String
  field :age, type: Integer
end

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
        InputQueryPerson.delete_all
        InputQueryDoc.delete_all
      end

      describe "#upload_arel" do
        before do
          @alice = InputQueryPerson.create!(name: "Alice", age: 30)
          @bob   = InputQueryPerson.create!(name: "Bob", age: 40)
        end

        it "uploads the id of each record by default" do
          skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

          count = input.upload_arel(InputQueryPerson.all)

          assert_equal 2, count
          assert_equal [@alice.id, @bob.id].sort, input.collect(&:to_a).flatten.sort
        end

        it "uploads a single named column" do
          skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

          count = input.upload_arel(InputQueryPerson.all, columns: [:name])

          assert_equal 2, count
          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "uploads a column named by a String" do
          skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

          input.upload_arel(InputQueryPerson.all, columns: ["name"])

          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "quotes a String column as the name of a column, rather than running it as SQL" do
          skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

          begin
            input.upload_arel(InputQueryPerson.all, columns: ["upper(name) AS uname"])
          rescue ActiveRecord::StatementInvalid
            nil # A database that rejects the name of a column that the table does not have.
          end

          refute_includes input.collect(&:to_a).flatten, "ALICE"
        end

        it "uploads multiple columns as arrays" do
          skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

          input.upload_arel(InputQueryPerson.all, columns: %i[name age])
          rows = input.collect(&:to_a).flatten(1).sort

          assert_equal [["Alice", 30], ["Bob", 40]], rows
        end

        it "uploads the rows in the order of the relation, and within its limit" do
          skip(QUERY_STREAMS_SKIP) unless QUERY_STREAMS

          assert_equal 1, input.upload_arel(InputQueryPerson.order(age: :desc).limit(1), columns: [:name])
          assert_equal ["Bob"], input.collect(&:to_a).flatten
        end

        it "uploads the columns that the batches of a relation select" do
          count = input.upload_arel(InputQueryPerson.select(:name, :age).in_batches(of: 1))

          assert_equal 2, count
          assert_equal [["Alice", 30], ["Bob", 40]], input.collect(&:to_a).flatten(1).sort
        end

        it "uploads the value of the one column that the batches of a relation select" do
          input.upload_arel(InputQueryPerson.select(:name).in_batches(of: 1))

          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "rejects the batches of a relation that selects no columns, rather than upload every column" do
          error = assert_raises(ArgumentError) { input.upload_arel(InputQueryPerson.in_batches(of: 1)) }

          assert_equal "Select the columns to upload before `in_batches`, such as `relation.select(:id).in_batches`",
                       error.message
          assert_equal 0, input.count
        end

        it "rejects columns for the batches of a relation" do
          error = assert_raises(ArgumentError) do
            input.upload_arel(InputQueryPerson.in_batches(of: 1), columns: [:name])
          end

          assert_equal "Select the columns to upload before `in_batches`, rather than with `columns:`", error.message
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

      it "uploads the batches of an Active Record relation" do
        assert_equal 2, job.upload(InputQueryPerson.select(:id).in_batches(of: 1))
        assert_equal 2, job.record_count
        assert_equal InputQueryPerson.ids.sort, job.input.collect(&:to_a).flatten.sort
      end

      it "rejects a block for an Active Record relation" do
        error = assert_raises(ArgumentError) { job.upload(InputQueryPerson.all, &:name) }

        assert_equal "Cannot supply both an object to upload, and a block.", error.message
      end

      it "rejects a block for a Mongoid query" do
        error = assert_raises(ArgumentError) { job.upload(InputQueryDoc.all) { |document| document["name"] } }

        assert_equal "Cannot supply both an object to upload, and a block.", error.message
      end

      it "rejects a file option for an Active Record relation" do
        error = assert_raises(ArgumentError) { job.upload(InputQueryPerson.all, file_name: "x.csv") }

        assert_equal "Unknown keyword arguments when uploading an ActiveRecord::Relation. " \
                     "Only accepts :category, :columns, or :slice_batch_size", error.message
      end

      it "rejects a file option for the batches of an Active Record relation, without naming columns" do
        error = assert_raises(ArgumentError) { job.upload(InputQueryPerson.select(:id).in_batches, file_name: "x.csv") }

        assert_equal "Unknown keyword arguments when uploading the batches of an ActiveRecord::Relation. " \
                     "Only accepts :category, or :slice_batch_size", error.message
      end

      it "rejects a file option for a range, without naming columns" do
        error = assert_raises(ArgumentError) { job.upload(1..10, file_name: "x.csv") }

        assert_equal "Unknown keyword arguments when uploading a Range. Only accepts :category, or :slice_batch_size",
                     error.message
      end

      it "rejects a file option for a Mongoid query" do
        error = assert_raises(ArgumentError) { job.upload(InputQueryDoc.all, file_name: "x.csv") }

        assert_equal "Unknown keyword arguments when uploading a Mongoid::Criteria. " \
                     "Only accepts :category, :columns, or :slice_batch_size", error.message
      end
    end
  end
end

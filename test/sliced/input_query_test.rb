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

# An embedded document of InputQueryDoc, read with a dotted column.
class InputQueryAddress
  include Mongoid::Document

  embedded_in :input_query_doc

  field :city, type: String
end

# A list of embedded documents of InputQueryDoc, read with a dotted column.
class InputQueryPhone
  include Mongoid::Document

  embedded_in :input_query_doc

  field :number, type: String
end

# Mongoid source for upload_mongo_query.
class InputQueryDoc
  include Mongoid::Document

  store_in collection: "input_query_docs"

  field :name, type: String
  field :age, type: Integer
  field :c, as: :city, type: String

  embeds_one :address, class_name: "InputQueryAddress"
  embeds_many :phones, class_name: "InputQueryPhone"
end

# A subclass, whose documents share the collection of InputQueryDoc, told apart by their `_type`.
class InputQueryChildDoc < InputQueryDoc
end

# A subclass of the subclass, whose documents are also those of InputQueryChildDoc.
class InputQueryGrandchildDoc < InputQueryChildDoc
end

# Another collection that InputQueryDoc is read from, by `with(collection:)` or `with_collection`.
INPUT_QUERY_OTHER_COLLECTION = "input_query_other_docs".freeze

module Sliced
  class InputQueryTest < Minitest::Test
    class QueryUploadJob < RocketJob::Job
      include RocketJob::Batch

      def perform(record)
        record
      end
    end

    class CsvUploadJob < RocketJob::Job
      include RocketJob::Batch

      input_category format: :csv

      def perform(record)
        record
      end
    end

    class JsonSchemaUploadJob < RocketJob::Job
      include RocketJob::Batch

      input_category format: :json, schema: {"fields" => [{"name" => "first", "type" => "integer"},
                                                          {"name" => "last", "type" => "integer"}]}

      def perform(record)
        record
      end
    end

    describe RocketJob::Sliced::Input do
      let(:collection_name) { :"rocket_job.slices.query_test" }

      let :input do
        RocketJob::Sliced::Input.new(collection_name: collection_name, slice_size: 100)
      end

      # An input category without a format, which uploads the value of each row of one column, otherwise an Array.
      let(:category) { RocketJob::Category::Input.new }

      before do
        input.delete_all
        InputQueryPerson.delete_all
        InputQueryDoc.delete_all
        InputQueryDoc.mongo_client[INPUT_QUERY_OTHER_COLLECTION].drop
      end

      after do
        input.drop
        InputQueryPerson.delete_all
        InputQueryDoc.delete_all
        InputQueryDoc.mongo_client[INPUT_QUERY_OTHER_COLLECTION].drop
      end

      describe "#upload_arel" do
        before do
          @alice = InputQueryPerson.create!(name: "Alice", age: 30)
          @bob   = InputQueryPerson.create!(name: "Bob", age: 40)
        end

        it "uploads the id of each record by default" do
          count = input.upload_arel(InputQueryPerson.all, category: category)

          assert_equal 2, count
          assert_equal [@alice.id, @bob.id].sort, input.collect(&:to_a).flatten.sort
        end

        it "uploads a single named column" do
          count = input.upload_arel(InputQueryPerson.all, category: category, columns: [:name])

          assert_equal 2, count
          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "uploads a column named by a String" do
          input.upload_arel(InputQueryPerson.all, category: category, columns: ["name"])

          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "quotes a String column as the name of a column, rather than running it as SQL" do
          begin
            input.upload_arel(InputQueryPerson.all, category: category, columns: ["upper(name) AS uname"])
          rescue ActiveRecord::StatementInvalid
            nil # A database that rejects the name of a column that the table does not have.
          end

          refute_includes input.collect(&:to_a).flatten, "ALICE"
        end

        it "uploads multiple columns as arrays" do
          input.upload_arel(InputQueryPerson.all, category: category, columns: %i[name age])
          rows = input.collect(&:to_a).flatten(1).sort

          assert_equal [["Alice", 30], ["Bob", 40]], rows
        end

        it "uploads the rows in the order of the relation, and within its limit" do
          assert_equal 1, input.upload_arel(InputQueryPerson.order(age: :desc).limit(1), category: category, columns: [:name])
          assert_equal ["Bob"], input.collect(&:to_a).flatten
        end

        it "uploads the columns that the batches of a relation select" do
          count = input.upload_arel(InputQueryPerson.select(:name, :age).in_batches(of: 1), category: category)

          assert_equal 2, count
          assert_equal [["Alice", 30], ["Bob", 40]], input.collect(&:to_a).flatten(1).sort
        end

        it "uploads the value of the one column that the batches of a relation select" do
          input.upload_arel(InputQueryPerson.select(:name).in_batches(of: 1), category: category)

          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "rejects the batches of a relation that selects no columns, rather than upload every column" do
          error = assert_raises(ArgumentError) { input.upload_arel(InputQueryPerson.in_batches(of: 1), category: category) }

          assert_equal "Select the columns to upload before `in_batches`, such as `relation.select(:id).in_batches`",
                       error.message
          assert_equal 0, input.count
        end

        it "rejects columns for the batches of a relation" do
          error = assert_raises(ArgumentError) do
            input.upload_arel(InputQueryPerson.in_batches(of: 1), category: category, columns: [:name])
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
          count = input.upload_mongo_query(InputQueryDoc.all, category: category)

          assert_equal 2, count
          assert_equal [@alice.id, @bob.id].sort, input.collect(&:to_a).flatten.sort
        end

        it "uploads a single named column" do
          input.upload_mongo_query(InputQueryDoc.all, category: category, columns: [:name])

          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "leaves the criteria of the caller as it was" do
          criteria = InputQueryDoc.where(name: "Alice").only(:name)
          options  = criteria.options.deep_dup

          input.upload_mongo_query(criteria, category: category, columns: [:age])

          assert_equal options, criteria.options
          assert_equal ["Alice"], criteria.collect(&:name)
        end

        it "uploads multiple columns as arrays" do
          input.upload_mongo_query(InputQueryDoc.all, category: category, columns: %i[name age])
          rows = input.collect(&:to_a).flatten(1).sort

          assert_equal [["Alice", 30], ["Bob", 40]], rows
        end

        it "uploads only the documents of a subclass and its own subclasses, not those of its parent" do
          InputQueryChildDoc.create!(name: "Carol", age: 50)
          InputQueryGrandchildDoc.create!(name: "Gina", age: 55)

          assert_equal 2, input.upload_mongo_query(InputQueryChildDoc.all, category: category, columns: [:name])
          assert_equal %w[Carol Gina], input.collect(&:to_a).flatten.sort
        end

        it "uploads from the collection that Mongoid reads the criteria from, such as within `with(collection:)`" do
          InputQueryDoc.with(collection: INPUT_QUERY_OTHER_COLLECTION) do |klass|
            klass.create!(name: "Dave", age: 60)
            input.upload_mongo_query(klass.all, category: category, columns: [:name])
          end

          assert_equal %w[Dave], input.collect(&:to_a).flatten
        end

        it "uploads from the collection that `with_collection` names" do
          InputQueryDoc.with(collection: INPUT_QUERY_OTHER_COLLECTION) { |klass| klass.create!(name: "Dave", age: 60) }
          input.upload_mongo_query(InputQueryDoc.with_collection(INPUT_QUERY_OTHER_COLLECTION), category: category, columns: [:name])

          assert_equal %w[Dave], input.collect(&:to_a).flatten
        end

        it "uploads none for a criteria that returns none" do
          assert_equal 0, input.upload_mongo_query(InputQueryDoc.none, category: category, columns: [:name])
          assert_equal 0, input.count
        end

        it "raises for a criteria of embedded documents" do
          doc   = InputQueryDoc.create!(name: "Erin", phones: [InputQueryPhone.new(number: "555-0100")])
          error = assert_raises(ArgumentError) do
            input.upload_mongo_query(doc.phones.where(number: "555-0100"), category: category, columns: [:number])
          end

          assert_equal "Upload a query of the documents that embed InputQueryPhone, since embedded documents are " \
                       "read within them rather than queried", error.message
        end

        it "uploads the fields of embedded documents by their dotted names" do
          InputQueryDoc.create!(
            name:    "Erin",
            address: InputQueryAddress.new(city: "Boston"),
            phones:  [InputQueryPhone.new(number: "555-0100"), InputQueryPhone.new(number: "555-0101")]
          )
          input.upload_mongo_query(InputQueryDoc.where(name: "Erin"), category: category, columns: ["address.city", "phones.number"])

          assert_equal [["Boston", %w[555-0100 555-0101]]], input.collect(&:to_a).flatten(1)
        end

        it "replaces a projection of the criteria that excludes fields with the columns" do
          input.upload_mongo_query(InputQueryDoc.without(:age), category: category, columns: [:name])

          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "reads outside the session of the caller" do
          InputQueryDoc.with_session do |session|
            # A read within this session raises Mongo::Error::SessionEnded.
            session.end_session
            input.upload_mongo_query(InputQueryDoc.all, category: category, columns: [:name])
          end

          assert_equal %w[Alice Bob], input.collect(&:to_a).flatten.sort
        end

        it "uploads a field by its alias" do
          InputQueryDoc.where(name: "Alice").update_all(c: "Boston")
          input.upload_mongo_query(InputQueryDoc.where(name: "Alice"), category: category, columns: [:city])

          assert_equal %w[Boston], input.collect(&:to_a).flatten
        end

        it "uploads in the order of the criteria, and within its limit" do
          input.upload_mongo_query(InputQueryDoc.order(age: :desc).limit(1), category: category, columns: [:name])

          assert_equal %w[Bob], input.collect(&:to_a).flatten
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
        assert_equal 2, job.upload(InputQueryPerson.all, columns: %i[name age])
        assert_equal 2, job.record_count
        assert_equal [["Alice", 30], ["Bob", 40]], job.input.collect(&:to_a).flatten(1).sort
      end

      it "gives perform the value of one column, or an Array of several, as Rocket Job 7 uploaded them" do
        records = lambda do
          list = []
          job.input.each { |slice| job.input_category.parse_records(slice.records) { |record| list << record } }
          job.input.delete_all
          list.sort
        end
        job.upload(InputQueryPerson.all, columns: [:name])

        # IOStreams holds the typed values of each row after the names of the columns.
        assert_equal [:array, %w[name]], [job.input.first.records.format, job.input.first.records.header]
        assert_equal %w[Alice Bob], records.call
        job.upload(InputQueryDoc.all, columns: %i[name age])

        assert_equal [["Alice", 30], ["Bob", 40]], records.call
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

      describe "into a category whose format reads the header row of a file" do
        let(:job) { CsvUploadJob.new }

        # Returns [Array] the header row, format and rows of each slice of the input, and the records that perform
        # receives from them.
        def uploaded
          slices  = job.input.sort_by(&:first_record_number)
          records = []
          slices.each { |slice| job.input_category.parse_records(slice.records) { |record| records << record } }
          [slices.collect { |slice| [slice.records.header, slice.records.format, slice.to_a] }, records]
        end

        it "writes an Active Record relation in the format, after the names of the columns, as a file of it holds" do
          assert_equal 2, job.upload(InputQueryPerson.order(:name), columns: %i[name age])
          assert_equal [[[%w[name age], :csv, %w[Alice,30 Bob,40]]],
                        [{"name" => "Alice", "age" => "30"}, {"name" => "Bob", "age" => "40"}]], uploaded
        end

        it "writes the batches of an Active Record relation in the format" do
          assert_equal 2, job.upload(InputQueryPerson.select(:name).in_batches(of: 1))
          assert_equal %w[Alice Bob], uploaded.last.collect { |record| record["name"] }.sort
        end

        it "writes a Mongoid query in the format, after the names of the fields" do
          assert_equal 2, job.upload(InputQueryDoc.order(name: 1), columns: %i[name age])
          assert_equal [[[%w[name age], :csv, %w[Alice,30 Bob,40]]],
                        [{"name" => "Alice", "age" => "30"}, {"name" => "Bob", "age" => "40"}]], uploaded
        end

        it "rejects a range" do
          assert_raises(ArgumentError) { job.upload(1..10) }
          assert_equal 0, job.input.count
        end
      end

      it "uploads into a category whose schema parses each Array of values, in a format without a header row" do
        job = JsonSchemaUploadJob.new

        assert_equal 3, job.upload(1..3)
        assert_equal({"first" => 1, "last" => 3}, job.input_category.parse(job.input.first.to_a.first))
      ensure
        job&.cleanup!
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

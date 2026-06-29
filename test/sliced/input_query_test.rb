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

# Mongoid source for upload_mongo_query.
class InputQueryDoc
  include Mongoid::Document

  store_in collection: "input_query_docs"

  field :name, type: String
  field :age, type: Integer
end

module Sliced
  class InputQueryTest < Minitest::Test
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

        it "honors a supplied block" do
          input.upload_arel(InputQueryPerson.all) { |model| model.name.upcase }
          assert_equal %w[ALICE BOB], input.collect(&:to_a).flatten.sort
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
  end
end

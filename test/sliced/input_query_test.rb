require_relative "../test_helper"
require "active_record"

ActiveRecord::Base.configurations = YAML.safe_load(ERB.new(File.read("test/config/database.yml")).result)
ActiveRecord::Base.establish_connection(:test)

ActiveRecord::Schema.define version: 0 do
  create_table :input_query_people, force: true do |t|
    t.string :name
    t.integer :age
  end

  create_table :input_query_members, force: true do |t|
    t.string :name
    t.string :nickname
    t.integer :status
  end

  create_table :input_query_posts, force: true do |t|
    t.integer :input_query_member_id
    t.boolean :published
  end
end

# ActiveRecord source for upload_arel.
class InputQueryPerson < ActiveRecord::Base
end

# A post of a member, for a relation that eager loads an association.
class InputQueryPost < ActiveRecord::Base
end

# ActiveRecord source whose readers return the value that the column holds, except for its nickname.
class InputQueryMember < ActiveRecord::Base
  has_many :input_query_posts

  alias_attribute :full_name, :name
  enum :status, {active: 0, inactive: 1}

  # Returns a value other than the one that the column holds when it holds none.
  def nickname
    super || "none"
  end
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
    class QueryJob < RocketJob::Job
      include RocketJob::Batch

      def perform(record)
        record
      end
    end

    describe RocketJob::Sliced::Input do
      # Returns [Array<String>] the deprecation warnings that Rocket Job reported while the block runs, with deprecation
      # warnings on, see DeprecationTest.
      def deprecation_warnings(enabled: true, &block)
        warnings = []
        previous = Warning[:deprecated]
        Warning[:deprecated] = enabled
        collect = lambda do |message, category: nil|
          warnings << message if category == :deprecated && message.include?("Rocket Job: ")
        end
        Warning.stub(:warn, collect, &block)
        warnings
      ensure
        Warning[:deprecated] = previous
      end

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
          warnings = deprecation_warnings { input.upload_arel(InputQueryPerson.all, columns: %i[name age]) }
          rows     = input.collect(&:to_a).flatten(1).sort

          assert_equal [["Alice", 30], ["Bob", 40]], rows
          assert_equal 1, warnings.size, warnings.inspect
          assert_includes warnings.first, "columns: with several names uploads each record as an Array"
        end

        it "honors a supplied block" do
          warnings = deprecation_warnings do
            input.upload_arel(InputQueryPerson.all) { |model| model.name.upcase }
          end

          assert_equal %w[ALICE BOB], input.collect(&:to_a).flatten.sort
          assert_equal 1, warnings.size, warnings.inspect
          assert_includes warnings.first, "a block passed with an Active Record relation receives each model"
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
          warnings = deprecation_warnings { input.upload_mongo_query(InputQueryDoc.all, columns: %i[name age]) }
          rows     = input.collect(&:to_a).flatten(1).sort

          assert_equal [["Alice", 30], ["Bob", 40]], rows
          assert_equal 1, warnings.size, warnings.inspect
          assert_includes warnings.first, "columns: with several names uploads each record as an Array"
        end

        it "honors a supplied block" do
          input.upload_mongo_query(InputQueryDoc.all) { |document| document["name"].downcase }

          assert_equal %w[alice bob], input.collect(&:to_a).flatten.sort
        end
      end

      describe "an upload that Rocket Job 8 stores differently" do
        let(:job) { QueryJob.new }

        before do
          @jack = InputQueryMember.create!(name: "Jack", nickname: "jj", status: :active)
          @jill = InputQueryMember.create!(name: "Jill", status: :inactive)
          InputQueryPost.create!(input_query_member_id: @jack.id, published: true)
          InputQueryDoc.create!(name: "Alice", age: 30)
          InputQueryDoc.create!(name: "Bob", age: 40)
        end

        after do
          job.cleanup!
          InputQueryMember.delete_all
          InputQueryPost.delete_all
        end

        # Returns [Array] the records that the job uploaded, in the order that it uploaded them.
        def records
          job.input.collect(&:to_a).flatten(1)
        end

        describe "with a block" do
          it "passes the block to upload, as Rocket Job 8 does, which still receives each model, and warns" do
            warnings = deprecation_warnings do
              job.upload(InputQueryMember.all) { |member| member["name"].upcase }
            end

            assert_equal %w[JACK JILL], records
            assert_equal 2, job.record_count
            assert_equal 1, warnings.size, warnings.inspect
            assert_includes warnings.first, "a block passed with an Active Record relation receives each model"
          end

          it "passes the block to upload for a Mongoid criteria, without a warning" do
            warnings = deprecation_warnings { job.upload(InputQueryDoc.all) { |document| document["name"] } }

            assert_equal %w[Alice Bob], records.sort
            assert_empty warnings
          end

          it "still raises for a block with an object that is not a query" do
            error = assert_raises(ArgumentError) { job.upload("data.csv") { |writer| writer << "a" } }

            assert_equal "Cannot supply both an object to upload, and a block.", error.message
          end

          it "warns once, at the line that uploads it, that the block receives a Hash of each row" do
            line     = __LINE__ + 2
            warnings = deprecation_warnings do
              job.upload_arel(InputQueryMember.all) { |member| member.name.upcase }
            end

            assert_equal %w[JACK JILL], records
            assert_equal 1, warnings.size, warnings.inspect
            assert warnings.first.start_with?("#{__FILE__}:#{line}: warning: Rocket Job: a block passed with an " \
                                              "Active Record relation receives each model"),
                   warnings.first
            assert_includes warnings.first, "in Rocket Job 8 it receives each row as a Hash of the columns that the " \
                                            "relation selects, with String keys, such as row[\"email\"]"
            assert_includes warnings.first, RocketJob::Deprecation::UPGRADE_GUIDE
          end

          it "does not warn for a Mongoid criteria, whose block already receives each document" do
            warnings = deprecation_warnings { job.upload_mongo_query(InputQueryDoc.all) { |document| document["name"] } }

            assert_equal %w[Alice Bob], records.sort
            assert_empty warnings
          end
        end

        describe "that eager loads associations" do
          it "warns once that it raises in Rocket Job 8" do
            warnings = deprecation_warnings { job.upload(InputQueryMember.includes(:input_query_posts)) }

            assert_equal [@jack.id, @jill.id], records
            assert_equal 1, warnings.size, warnings.inspect
            assert_includes warnings.first, "uploading an Active Record relation that uses includes raises " \
                                            "ArgumentError in Rocket Job 8"
          end

          it "names each method that eager loads" do
            relation = InputQueryMember.preload(:input_query_posts).eager_load(:input_query_posts)
            warnings = deprecation_warnings { job.upload(relation, columns: [:name]) }

            assert_equal %w[Jack Jill], records
            assert_equal 1, warnings.size, warnings.inspect
            assert_includes warnings.first, "that uses preload and eager_load raises ArgumentError"
          end

          it "also warns for the block" do
            warnings = deprecation_warnings do
              job.upload_arel(InputQueryMember.includes(:input_query_posts)) { |member| member.input_query_posts.size }
            end

            assert_equal [1, 0], records
            assert_equal 2, warnings.size, warnings.inspect
            assert_includes warnings.first, "that uses includes raises ArgumentError"
            assert_includes warnings.last, "a block passed with an Active Record relation"
          end
        end

        describe "of several columns" do
          it "warns once that Rocket Job 8 uploads a Hash of each relation's row" do
            warnings = deprecation_warnings { job.upload(InputQueryMember.all, columns: %i[name status]) }

            assert_equal [%w[Jack active], %w[Jill inactive]], records
            assert_equal 1, warnings.size, warnings.inspect
            assert_includes warnings.first, "columns: with several names uploads each record as an Array of their " \
                                            "values, but Rocket Job 8 uploads a Hash of the columns by name, with " \
                                            "String keys, such as record[\"name\"]"
          end

          it "warns once that Rocket Job 8 uploads a Hash of each document of a Mongoid criteria" do
            warnings = deprecation_warnings { job.upload(InputQueryDoc.all, columns: %i[name age]) }

            assert_equal [["Alice", 30], ["Bob", 40]], records.sort
            assert_equal 1, warnings.size, warnings.inspect
            assert_includes warnings.first, "columns: with several names uploads each record as an Array"
          end

          it "warns through the upload_arel of a job" do
            warnings = deprecation_warnings { job.upload_arel(InputQueryMember.all, :name, :status) }

            assert_equal [%w[Jack active], %w[Jill inactive]], records
            assert_equal 1, warnings.size, warnings.inspect
            assert_includes warnings.first, "columns: with several names"
          end
        end

        describe "of one column" do
          it "does not warn" do
            warnings = deprecation_warnings do
              job.upload(InputQueryMember.all)
              job.upload(InputQueryMember.all, columns: [:name])
              job.upload(InputQueryDoc.all)
              job.upload(InputQueryDoc.all, columns: [:name])
            end

            assert_equal 8, job.record_count
            assert_empty warnings
          end
        end

        describe "of a column whose reader returns another value" do
          it "warns once, at the line that uploads it, naming the model and the column, but not the values" do
            InputQueryMember.create!(name: "Joe")
            line     = __LINE__ + 1
            warnings = deprecation_warnings { job.upload(InputQueryMember.all, columns: [:nickname]) }

            assert_equal %w[jj none none], records
            assert_equal 1, warnings.size, warnings.inspect
            assert_equal "#{__FILE__}:#{line}: warning: Rocket Job: InputQueryMember#nickname returns a value other " \
                         "than the one that its column holds, which Rocket Job 8 uploads instead, as pluck returns " \
                         "it, rather than calling the reader: to keep the reader's value, pass a block, which in " \
                         "Rocket Job 8 receives each row as a Hash of the columns, and apply the reader's logic in " \
                         "it, or in perform, see #{RocketJob::Deprecation::UPGRADE_GUIDE}\n",
                         warnings.first
          end

          it "warns for it among several columns" do
            warnings = deprecation_warnings { job.upload(InputQueryMember.all, columns: %i[name nickname]) }

            assert_equal [%w[Jack jj], %w[Jill none]], records
            assert_equal 2, warnings.size, warnings.inspect
            assert_includes warnings.first, "columns: with several names"
            assert_includes warnings.last, "InputQueryMember#nickname returns a value other than"
          end

          it "warns through upload_arel" do
            warnings = deprecation_warnings { input.upload_arel(InputQueryMember.all, columns: [:nickname]) }

            assert_equal %w[jj none], input.collect(&:to_a).flatten
            assert_equal 1, warnings.size, warnings.inspect
            assert_includes warnings.first, "InputQueryMember#nickname returns a value other than"
          end

          it "stops comparing the column once it has warned" do
            reads    = 0
            reader   = lambda do
              reads += 1
              "stubbed"
            end
            warnings = InputQueryMember.stub_any_instance(:nickname, reader) do
              deprecation_warnings { job.upload(InputQueryMember.all, columns: [:nickname]) }
            end

            assert_equal %w[stubbed stubbed], records
            assert_equal 1, warnings.size, warnings.inspect
            # Once for each row to upload it, and once more to compare it for the first row only.
            assert_equal 3, reads
          end

          it "does not warn for a column without a reader of its own, an alias or an enum" do
            warnings = deprecation_warnings do
              job.upload(InputQueryMember.all, columns: [:name])
              job.upload(InputQueryMember.all, columns: [:full_name])
              job.upload(InputQueryMember.all, columns: [:status])
            end

            assert_equal %w[Jack Jill Jack Jill active inactive], records
            assert_empty warnings
          end
        end

        describe "while deprecation warnings are off" do
          it "reports nothing" do
            warnings = deprecation_warnings(enabled: false) do
              job.upload_arel(InputQueryMember.includes(:input_query_posts)) { |member| member.name.upcase }
              job.upload(InputQueryMember.all, columns: %i[name nickname])
              job.upload(InputQueryDoc.all, columns: %i[name age])
            end

            assert_equal 6, job.record_count
            assert_empty warnings
          end

          it "does not compare the readers" do
            reads    = 0
            reader   = lambda do
              reads += 1
              "stubbed"
            end
            warnings = InputQueryMember.stub_any_instance(:nickname, reader) do
              deprecation_warnings(enabled: false) { job.upload(InputQueryMember.all, columns: [:nickname]) }
            end

            assert_equal %w[stubbed stubbed], records
            assert_empty warnings
            # Only once for each row, to upload it.
            assert_equal 2, reads
          end
        end
      end
    end
  end
end

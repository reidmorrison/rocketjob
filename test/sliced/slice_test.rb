require_relative "../test_helper"

module Sliced
  class SliceTest < Minitest::Test
    describe RocketJob::Sliced::Slice do
      let :slices do
        RocketJob::Sliced::Slice.with_collection(:slice_test_specific)
      end

      let :collection_name do
        :slice_test_specific
      end

      let :slice do
        RocketJob::Sliced::Slice.new(collection_name: collection_name)
      end

      let :dataset do
        ["hello", "world", 1, 3.25, Time.at(Time.now.to_i), [1, 2], {"a" => 43}, true, false, :symbol, nil]
      end

      let :exception do
        RocketJob.blah
      rescue StandardError => e
        e
      end

      before do
        slices.delete_all
      end

      describe "#size" do
        it "return the records size" do
          slice << "hello"

          assert_equal 1, slice.size
        end
      end

      describe "#<<" do
        it "add records" do
          assert_equal 0, slice.size
          slice << "hello"

          assert_equal 1, slice.size
          slice << "next"

          assert_equal 2, slice.size
          assert_equal "hello", slice.first
        end
      end

      describe "#to_a" do
        it "return the array of records" do
          slice << "hello"
          slice << "world"

          assert_equal 2, slice.size
          arr = slice.to_a

          assert_equal %w[hello world], arr, -> { arr.ai }
        end
      end

      describe "#records" do
        it "return the array of records" do
          slice << "hello"
          slice << "world"

          assert_equal 2, slice.size
          arr = slice.records

          assert_equal %w[hello world], arr.to_a, -> { arr.ai }
        end

        it "set the array of records" do
          slice << "hello"
          slice << "world"

          assert_equal 2, slice.size
          slice.records = %w[hello world]

          assert_equal 2, slice.size
          arr = slice.records

          assert_equal %w[hello world], arr, -> { arr.ai }
        end
      end

      describe "#find" do
        it "returned document has the same collection" do
          slice << "1"
          slice << "2"
          slice.save!

          assert found_slice = slices.find(slice.id)
          assert_equal collection_name, found_slice.collection_name
        end
      end

      describe "#first" do
        it "returned document has the same collection" do
          slice << "1"
          slice << "2"
          slice.save!

          assert found_slice = slices.first
          assert_equal collection_name, found_slice.collection_name
        end
      end

      describe "#fail" do
        it "without exception" do
          slice.start
          slice.worker_name = "me"

          assert_nil slice.failure_count
          slice.fail

          assert_equal 1, slice.failure_count
          assert_nil slice.exception
        end

        it "with exception" do
          slice.start
          slice.worker_name = "me"
          slice.fail!(exception)

          assert_equal 1, slice.failure_count
          assert slice.exception
          assert_equal exception.class.name, slice.exception.class_name
          assert_equal exception.message, slice.exception.message
          assert_equal exception.backtrace, slice.exception.backtrace
          assert_equal "me", slice.exception.worker_name
          assert_equal collection_name, slice.collection_name
        end
      end

      describe "#fail_on_exception!" do
        it "fails the slice with the exception" do
          slice.start
          slice.worker_name = "me"
          slice.fail_on_exception! { raise(ArgumentError, "first") }

          assert_predicate slice, :failed?
          assert_equal "first", slice.exception.message
          assert_equal "me", slice.exception.worker_name
        end

        it "records the exception of a slice that has already failed" do
          slice.start
          slice.fail(RuntimeError.new("first"))
          slice.worker_name = "me"
          slice.fail_on_exception! { raise(ArgumentError, "second") }

          assert_equal "ArgumentError", slice.exception.class_name
          assert_equal "second", slice.exception.message
          assert_equal "me", slice.exception.worker_name
        end

        it "re-raises the exception when asked" do
          slice.start
          assert_raises(ArgumentError) { slice.fail_on_exception!(true) { raise(ArgumentError, "first") } }
        end
      end

      describe "#save" do
        it "persists" do
          slice << "1"
          slice << "2"

          assert slice.save!
          assert_equal collection_name, slice.collection_name
          assert found_slice = slices.find(slice.id)
          assert_equal slice.state, found_slice.state
          assert_equal slice.to_a, found_slice.to_a
          assert_equal collection_name, found_slice.collection_name
        end

        it "test_it" do
          slice << "1"
          slice << "2"

          assert slice.save!
          assert found_slice = slices.find(slice.id)
          assert_equal slice.state, found_slice.state
          assert_equal slice.to_a, found_slice.to_a
          assert_equal collection_name, found_slice.collection_name
        end

        it "works for state machine" do
          slice << "1"
          slice << "2"

          assert slice.start!
          assert found_slice = slices.find(slice.id)
          assert_equal slice.state, found_slice.state
          assert_equal slice.to_a, found_slice.to_a
          assert_equal collection_name, found_slice.collection_name
        end

        it "updates existing record" do
          slice << "1"
          slice << "2"

          assert slice.start!
          assert slice.complete!
          assert found_slice = slices.find(slice.id)
          assert_equal slice.state, found_slice.state
          assert_equal slice.to_a, found_slice.to_a
          assert_equal collection_name, found_slice.collection_name
        end
      end

      it "transition states" do
        assert_equal :queued, slice.state
        slice.start

        assert_equal :running, slice.state
        slice.fail

        assert_equal :failed, slice.state
        slice.retry

        assert_equal :queued, slice.state
        slice.start

        assert_equal :running, slice.state
        slice.complete

        assert_equal :completed, slice.state
      end

      describe "#replace_record" do
        it "replaces the record at the index, and saves it with the slice" do
          slice.records = %w[same same other]
          slice.replace_record(1, "changed")
          slice.save!

          assert_equal %w[same changed other], slices.find(slice.id).records
        end

        it "raises for an index without a record" do
          slice.records = %w[only]

          assert_raises(IndexError) { slice.replace_record(1, "changed") }
          assert_equal %w[only], slice.records
        end
      end

      describe "#records_from" do
        it "returns the records from the record number on" do
          slice.records = %w[a b c]

          assert_equal %w[b c], slice.records_from(2)
          assert_equal %w[a b c], slice.records_from(1)
          assert_empty slice.records_from(4)
        end
      end

      describe "#delete_record" do
        it "removes only the record at the index, and saves it with the slice" do
          slice.records = %w[same same other]

          assert_equal "same", slice.delete_record(1)
          slice.save!

          assert_equal %w[same other], slices.find(slice.id).records
        end

        it "raises for an index without a record" do
          slice.records = %w[only]

          assert_raises(IndexError) { slice.delete_record(1) }
          assert_equal %w[only], slice.records
        end
      end

      describe "the rows of a file" do
        let(:rows) { IOStreams::Slice.new(["Jack,21", "", "Jill,22"], header: %w[Name AGE], format: :csv) }

        it "keep their header row when a record is replaced or removed" do
          slice.records = rows
          slice.replace_record(0, "Jack,22")
          slice.delete_record(1)
          slice.save!
          found = slices.find(slice.id)

          assert_equal ["Jack,22", "Jill,22"], found.records.to_a
          assert_equal %w[Name AGE], found.records.header
        end

        it "read back keep their header row when a record is replaced or removed" do
          slice.records = rows
          slice.save!
          found = slices.find(slice.id)
          found.replace_record(0, "Jack,22")

          assert_equal "", found.delete_record(1)
          found.save!
          saved = slices.find(slice.id).records

          assert_equal ["Jack,22", "Jill,22"], saved.to_a
          assert_equal %w[Name AGE], saved.header
          assert_equal :csv, saved.format
        end

        it "that are frozen, as IOStreams hands them on, are changed in a copy that keeps what they carry" do
          frozen        = IOStreams::Slice.new(["Jack,21", "", "Jill,22"], header: %w[Name AGE].freeze, format: :array,
                                               blank_rows: false).freeze
          slice.records = frozen
          slice.replace_record(0, "Jack,22")

          assert_equal "", slice.delete_record(1)
          assert_kind_of IOStreams::Slice, slice.records
          assert_equal ["Jack,22", "Jill,22"], slice.records.to_a
          assert_equal %w[Name AGE], slice.records.header
          assert_equal :array, slice.records.format
          refute_predicate slice.records, :blank_rows?
          assert_equal ["Jack,21", "", "Jill,22"], frozen
        end

        it "keeps the header row and format that they carry" do
          slice.records = rows
          slice.save!
          found = slices.find(slice.id)

          assert_kind_of IOStreams::Slice, found.records
          assert_equal rows.to_a, found.records.to_a
          assert_equal %w[Name AGE], found.records.header
          assert_equal :csv, found.records.format
        end

        it "keep their header row and format when a changed copy of them is assigned back" do
          slice.records = rows
          slice.save!
          found         = slices.find(slice.id)
          records       = found.to_a.dup
          records[2]    = "Jill,23"
          found.records = records
          found.save!
          saved = slices.find(slice.id).records

          assert_kind_of IOStreams::Slice, saved
          assert_equal ["Jack,21", "", "Jill,23"], saved.to_a
          assert_equal %w[Name AGE], saved.header
          assert_equal :csv, saved.format
        end

        it "of a query keep their rows of nulls as records, from a record number or when a changed copy is assigned" do
          slice.records = IOStreams::Slice.new([["Jack", 21], [nil, nil]], header: %w[name age].freeze, format: :array,
                                               blank_rows: false).freeze
          rest          = slice.records_from(2)

          assert_equal [[nil, nil]], rest.to_a
          refute_predicate rest, :blank_rows?

          records       = slice.records.to_a
          records[0]    = ["Jill", 22]
          slice.records = records

          assert_equal [["Jill", 22], [nil, nil]], slice.records.to_a
          assert_equal %w[name age], slice.records.header
          assert_equal :array, slice.records.format
          refute_predicate slice.records, :blank_rows?
        end

        it "are replaced as they are by records that are not rows" do
          slice.records = rows
          slice.records = [{"name" => "Jack"}]

          assert_equal [{"name" => "Jack"}], slice.records
          assert_instance_of Array, slice.records
        end

        it "from a record number keep their header row and format" do
          slice.records = rows
          rest          = slice.records_from(2)

          assert_equal ["", "Jill,22"], rest.to_a
          assert_equal %w[Name AGE], rest.header
          assert_equal :csv, rest.format
          assert_equal rows.to_a, slice.records_from(1).to_a
          assert_empty slice.records_from(4)
        end

        it "that cannot be read raise when they are used, rather than when the slice is read" do
          slice.records = rows
          slice.save!
          stored   = slices.collection.find(_id: slice.id).first["records"]
          document = Hash.from_bson(BSON::ByteBuffer.new(stored.data))
          document["s"]["format"] = "no_such_format"
          slices.collection.update_one({_id: slice.id}, {"$set" => {"records" => BSON::Binary.new(document.to_bson.to_s)}})
          found = slices.find(slice.id)

          error = assert_raises(ArgumentError) { found.records }
          assert_includes error.message, "no_such_format"

          found.records = %w[replaced]

          assert_equal %w[replaced], found.records
        end

        it "are saved as binary, so that Rocket Job 7 raises rather than read them as records" do
          slice.records = rows
          slice.save!
          stored   = slices.collection.find(_id: slice.id).first["records"]
          document = Hash.from_bson(BSON::ByteBuffer.new(stored.data))

          assert_kind_of BSON::Binary, stored
          assert_equal RocketJob::Sliced::Slice::ROWS_GUARD, document["r"]
          assert_equal rows.to_h, document["s"]
        end
      end
    end
  end
end

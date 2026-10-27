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

      describe "#record_number_at" do
        it "numbers records that are not the rows of a file by their place, from the first record number" do
          slice.first_record_number = 51
          slice.records             = %w[a b c]

          assert_equal [51, 53], [slice.record_number_at(0), slice.record_number_at(2)]
          assert_nil slice.line_number_at(0)
        end

        it "numbers the record being processed, also in an empty slice" do
          slice.first_record_number = 51

          assert_equal 51, slice.current_record_number
          assert_nil slice.current_line_number
          slice.records                  = %w[a b c]
          slice.processing_record_number = 3

          assert_equal 53, slice.current_record_number
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
        let(:rows) do
          IOStreams::Slice.new(["Jack,21", "", "Jill,22"], header: %w[Name AGE], format: :csv, line_number: 2,
                                                           record_number: 1)
        end

        # The line and record number of each row of the supplied slice of rows.
        def numbers_of(rows)
          rows.each.map { |_row, line_number, record_number| [line_number, record_number] }
        end

        it "keep their header row when a record is replaced or removed" do
          slice.records = rows
          slice.replace_record(0, "Jack,22")
          slice.delete_record(1)
          slice.save!
          found = slices.find(slice.id)

          assert_equal ["Jack,22", "Jill,22"], found.records.rows
          assert_equal %w[Name AGE], found.records.header
        end

        it "keep the line and record number of each row when a record is replaced or removed" do
          slice.records = rows
          slice.replace_record(-1, "Jill,23")

          assert_equal "", slice.delete_record(1)
          slice.save!
          found = slices.find(slice.id)

          assert_equal ["Jack,21", "Jill,23"], found.records.rows
          assert_equal [[2, 1], [4, 3]], numbers_of(found.records)
        end

        it "raise for an index without a record, rather than change the rows" do
          slice.records = rows

          assert_raises(IndexError) { slice.replace_record(3, "Joe,23") }
          assert_raises(IndexError) { slice.delete_record(-4) }
          assert_equal rows, slice.records
        end

        it "keep the numbers of the rows after a quoted value with line breaks when saved" do
          rows = IOStreams::Slice.new([], header: %w[Name NOTE], format: :csv)
          rows.add("Jack,one", line_number: 2, record_number: 1)
          rows.add("Jill,\"line one\nline two\"", line_number: 3, record_number: 2)
          rows.add("Joe,three", line_number: 5, record_number: 3)
          slice.records = rows
          slice.save!

          assert_equal [[2, 1], [3, 2], [5, 3]], numbers_of(slices.find(slice.id).records)
        end

        it "are read as an Array of rows by the slice" do
          slice.records = rows

          assert_equal rows.rows, slice.to_a
          assert_equal "Jill,22", slice.at(2)
          assert_equal ["Jack,21"], slice.first(1)
          assert_equal [["Jack,21", 0], ["", 1], ["Jill,22", 2]], slice.each_with_index.to_a
        end

        it "answer their own record and line numbers, which they keep when a record is removed" do
          slice.first_record_number = 51
          slice.records             = rows
          slice.delete_record(0)

          assert_equal [2, 3], [slice.record_number_at(0), slice.record_number_at(1)]
          assert_equal [3, 4], [slice.line_number_at(0), slice.line_number_at(1)]
          slice.processing_record_number = 2

          assert_equal 3, slice.current_record_number
          assert_equal 4, slice.current_line_number
        end

        it "are numbered from the first record number, without lines, when assigned in an Array" do
          slice.first_record_number = 51
          slice.records             = rows
          slice.records             = slice.map(&:upcase)

          assert_equal 52, slice.record_number_at(1)
          assert_nil slice.line_number_at(1)
        end

        it "are numbered from the first record number, without lines, when they have no numbers" do
          slice.first_record_number = 51
          slice.records             = IOStreams::Slice.new(["Jack,21"], header: %w[Name AGE], format: :csv)

          assert_equal 51, slice.current_record_number
          assert_nil slice.current_line_number
        end

        it "name the record that failed" do
          slice.records                  = rows
          slice.processing_record_number = 3
          slice.fail(RuntimeError.new("bad"))

          assert_equal "Jill,22", slice.failed_record
        end

        it "keeps the header row and format that they carry" do
          slice.records = rows
          slice.save!
          found = slices.find(slice.id)

          assert_kind_of IOStreams::Slice, found.records
          assert_equal rows.rows, found.records.rows
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
          assert_equal ["Jack,21", "", "Jill,23"], saved.rows
          assert_equal %w[Name AGE], saved.header
          assert_equal :csv, saved.format
        end

        it "keep how they are read when a changed copy of typed rows is assigned back, such as rows not to cast again" do
          slice.records = IOStreams::Slice.new([["Jack", 21], [nil, nil]], header: %w[name age], format: :array,
                                                                            typed: true, blank_rows: false)
          slice.save!
          found         = slices.find(slice.id)
          records       = found.to_a.dup
          records[0]    = ["Jack", 22]
          found.records = records
          found.save!
          saved = slices.find(slice.id).records

          assert_equal [["Jack", 22], [nil, nil]], saved.rows
          assert_equal [%w[name age], :array, true, false], [saved.header, saved.format, saved.typed?, saved.blank_rows?]
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

          assert_equal ["", "Jill,22"], rest.rows
          assert_equal [[3, 2], [4, 3]], numbers_of(rest)
          assert_equal %w[Name AGE], rest.header
          assert_equal :csv, rest.format
          assert_equal rows.rows, slice.records_from(1).rows
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

    describe "a failed slice saved by Rocket Job 7" do
      let(:slices) { RocketJob::Sliced::Slice.with_collection(:slice_test_v7) }

      before do
        slices.delete_all
      end

      # Returns the records of a slice of the supplied class as Rocket Job 7 saved them: as they are, or the BSON of
      # {"r" => records}, compressed, or compressed and encrypted.
      def saved_by_v7(slice_class, records)
        if slice_class == RocketJob::Sliced::CompressedSlice
          BSON::Binary.new(Zlib::Deflate.deflate({"r" => records}.to_bson.to_s))
        elsif slice_class == RocketJob::Sliced::EncryptedSlice
          bson = {"r" => records}.to_bson.to_s
          BSON::Binary.new(SymmetricEncryption.cipher.binary_encrypt(bson, random_iv: true, compress: true))
        else
          records
        end
      end

      [RocketJob::Sliced::Slice, RocketJob::Sliced::CompressedSlice, RocketJob::Sliced::EncryptedSlice].each do |slice_class|
        {
          "lines"  => ["Jack,21", "", "Jill,22"],
          "hashes" => [{"name" => "Jack"}, {"name" => "Jill"}, {"name" => "Joe"}]
        }.each_pair do |kind, records|
          describe "#{slice_class.name.demodulize} of #{kind}" do
            let(:id) { BSON::ObjectId.new }

            let(:slice) do
              slices.collection.insert_one(
                "_id"                      => id,
                "_type"                    => slice_class.name,
                "state"                    => "failed",
                "first_record_number"      => 101,
                "processing_record_number" => 2,
                "failure_count"            => 1,
                "exception"                => {"class_name" => "RuntimeError", "message" => "bad"},
                "records"                  => saved_by_v7(slice_class, records)
              )
              slices.find(id)
            end

            it "reads its records as an Array" do
              assert_instance_of slice_class, slice
              assert_instance_of Array, slice.records
              assert_equal records, slice.to_a
              assert_equal records[1], slice.failed_record
              assert_equal records[1..], slice.records_from(2)
              assert_equal 102, slice.current_record_number
            end

            it "saves a replaced or removed record in the same form" do
              slice.replace_record(1, records[0])

              assert_equal records[2], slice.delete_record(2)
              slice.save!
              saved  = slices.find(id)
              stored = slices.collection.find(_id: id).first["records"]

              assert_equal [records[0], records[0]], saved.records
              assert_instance_of Array, saved.records
              if slice_class == RocketJob::Sliced::Slice
                assert_equal [records[0], records[0]], stored
              else
                assert_kind_of BSON::Binary, stored
              end
            end
          end
        end
      end
    end
  end
end

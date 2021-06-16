require_relative "../test_helper"

module Sliced
  class EncryptedSliceTest < Minitest::Test
    describe RocketJob::Sliced::EncryptedSlice do
      let :slices do
        RocketJob::Sliced::EncryptedSlice.with_collection(:slice_test_specific)
      end

      let :collection_name do
        :slice_test_specific
      end

      let :slice do
        RocketJob::Sliced::EncryptedSlice.new(collection_name: collection_name)
      end

      let :dataset do
        ["hello", "world", 1, 3.25, Time.at(Time.now.to_i), [1, 2], {"a" => 43}, true, false, nil]
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
          assert_equal 1, slice.size, slice.records
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
          slice.processing_record_number = 21
          slice.worker_name              = "me"
          slice.fail!(exception)
          assert_equal 1, slice.failure_count
          assert slice.exception
          assert_equal exception.class.name, slice.exception.class_name
          assert_equal exception.message, slice.exception.message
          assert_equal exception.backtrace, slice.exception.backtrace
          assert_equal "me", slice.exception.worker_name
          assert_equal 21, slice.processing_record_number
          assert_equal collection_name, slice.collection_name
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

      describe "with slice" do
        let(:slice) do
          RocketJob::Sliced::EncryptedSlice.new(
            collection_name:          collection_name,
            records:                  dataset,
            exception:                RocketJob::JobException.from_exception(exception),
            worker_name:              "worker",
            failure_count:            3,
            processing_record_number: 21
          )
        end

        describe "#new" do
          it "creates a new slice" do
            assert_equal collection_name, slice.collection_name
          end
        end

        describe "serialization" do
          it "saves and reads back" do
            slice.save!
            found_slice = slices.find(slice.id)
            assert_equal slice.id, found_slice.id
            assert_equal :queued, found_slice.state
            assert_equal dataset, found_slice.records
            assert_equal dataset, found_slice.to_a
            assert_equal "worker", found_slice.worker_name
            assert_equal 3, found_slice.failure_count
            assert found_slice.exception, -> { found_slice.as_attributes.ai }
            assert_equal exception.class.name, found_slice.exception.class_name
            assert_equal exception.message, found_slice.exception.message
            assert_equal exception.backtrace, found_slice.exception.backtrace
            assert_equal 21, found_slice.processing_record_number
            assert found_slice.is_a?(RocketJob::Sliced::EncryptedSlice)
          end
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
    end
  end
end

require_relative "../test_helper"

module Sliced
  class CompressedSliceTest < Minitest::Test
    describe RocketJob::Sliced::CompressedSlice do
      let :collection_name do
        :slice_test_specific
      end

      let :slices do
        RocketJob::Sliced::CompressedSlice.with_collection(collection_name)
      end

      let :slice do
        RocketJob::Sliced::CompressedSlice.new(collection_name: collection_name)
      end

      let :dataset do
        ["hello", "world", 1, 3.25, Time.at(Time.now.to_i), [1, 2], {"a" => 43}, true, false, nil]
      end

      let :slice_with_records do
        dataset.each { |record| slice << record }
        slice
      end

      before do
        slices.delete_all
      end

      describe "#parse_records" do
        it "Decompresses binary" do
          str  = {"r" => dataset}.to_bson.to_s
          data = Zlib::Deflate.deflate(str)

          slice_with_records.attributes["records"] = BSON::Binary.new(data)

          result = slice_with_records.send(:parse_records)

          assert_equal dataset, result
          assert_equal dataset, slice_with_records.records
        end
      end

      describe "#serialize_records" do
        it "Serializes the records to binary" do
          result = slice_with_records.send(:serialize_records)

          assert_kind_of BSON::Binary, result

          compressed_str   = result.data
          uncompressed_str = Zlib::Inflate.inflate(compressed_str)
          records          = Hash.from_bson(BSON::ByteBuffer.new(uncompressed_str))["r"]

          assert_equal dataset, records
        end
      end

      describe "#save" do
        it "persists" do
          assert slice_with_records.save!
          assert found_slice = slices.find(slice_with_records.id)
          assert_equal dataset, found_slice.to_a
        end

        it "updates existing record" do
          assert slice_with_records.start!
          assert slice_with_records.complete!
          assert found_slice = slices.find(slice_with_records.id)
          assert_equal dataset, found_slice.to_a
        end
      end
    end
  end
end

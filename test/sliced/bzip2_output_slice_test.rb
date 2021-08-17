require_relative "../test_helper"

module Sliced
  class BZip2OutputSliceTest < Minitest::Test
    describe RocketJob::Sliced::BZip2OutputSlice do
      let :collection_name do
        :slice_test_specific
      end

      let :slices do
        RocketJob::Sliced::BZip2OutputSlice.with_collection(collection_name)
      end

      let :slice do
        RocketJob::Sliced::BZip2OutputSlice.new(collection_name: collection_name)
      end

      let :dataset do
        ["hello", "world", 1, 3.25, Time.at(Time.now.to_i), [1, 2], {"a" => 43}, true, false, nil]
      end

      let :compressed_dataset do
        lines = dataset.to_a.join("\n") + "\n"
        s     = StringIO.new
        IOStreams::Bzip2::Writer.stream(s) { |io| io.write(lines) }
        s.string
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
          slice_with_records.attributes["records"] = BSON::Binary.new(compressed_dataset)

          result = slice_with_records.send(:parse_records)
          assert_equal [compressed_dataset], result
          assert_equal [compressed_dataset], slice_with_records.records
        end
      end

      describe "#serialize_records" do
        it "Serializes the records to binary" do
          result = slice_with_records.send(:serialize_records)
          assert result.is_a?(BSON::Binary)
          assert_equal compressed_dataset, result.data
        end
      end

      describe "#save" do
        it "persists" do
          assert slice_with_records.save!
          assert found_slice = slices.find(slice_with_records.id)
          assert_equal [compressed_dataset], found_slice.to_a
        end

        it "updates existing record" do
          assert slice_with_records.start!
          assert slice_with_records.complete!
          assert found_slice = slices.find(slice_with_records.id)
          assert_equal [compressed_dataset], found_slice.to_a
        end
      end
    end
  end
end

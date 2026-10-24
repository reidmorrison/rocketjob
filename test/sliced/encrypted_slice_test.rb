require_relative "../test_helper"

module Sliced
  class EncryptedSliceTest < Minitest::Test
    describe RocketJob::Sliced::EncryptedSlice do
      let :collection_name do
        :slice_test_specific
      end

      let :slices do
        RocketJob::Sliced::EncryptedSlice.with_collection(collection_name)
      end

      let :slice do
        RocketJob::Sliced::EncryptedSlice.new(collection_name: collection_name)
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
        it "Decrypts records" do
          str  = {"r" => dataset}.to_bson.to_s
          data = SymmetricEncryption.cipher.binary_encrypt(str, random_iv: true, compress: true)

          slice_with_records.attributes["records"] = BSON::Binary.new(data)

          result = slice_with_records.send(:parse_records)

          assert_equal dataset, result
          assert_equal dataset, slice_with_records.records
        end
      end

      describe "#serialize_records" do
        it "Encrypts the records" do
          result = slice_with_records.send(:serialize_records)

          assert_kind_of BSON::Binary, result

          encrypted_str = result.data

          header = SymmetricEncryption::Header.new
          header.parse(encrypted_str)
          # Use the header that is present to decrypt the data, since its version could be different
          decrypted_str = header.cipher.binary_decrypt(encrypted_str, header: header)

          records = Hash.from_bson(BSON::ByteBuffer.new(decrypted_str))["r"]

          assert_equal dataset, records
        end
      end

      describe "#save" do
        it "persists a slice without records" do
          assert slice_with_records.save!
          slice_with_records.records = []

          assert slice_with_records.save!
          assert found_slice = slices.find(slice_with_records.id)
          assert_equal [], found_slice.to_a
        end

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

      describe "the rows of a file" do
        let(:rows) { IOStreams::Slice.new(["Jack,21", "Jill,22"], header: %w[Name AGE], format: :csv) }

        it "keeps the header row and format that they carry" do
          slice.records = rows
          slice.save!
          found = slices.find(slice.id)

          assert_kind_of IOStreams::Slice, found.records
          assert_equal rows.rows, found.records.rows
          assert_equal %w[Name AGE], found.records.header
          assert_equal :csv, found.records.format
        end

        it "saves ROWS_GUARD where Rocket Job 7 reads the records, so that it raises rather than process none" do
          slice.records = rows
          document      = Hash.from_bson(BSON::ByteBuffer.new(slice.send(:decode_records, slice.send(:serialize_records).data)))

          assert_equal RocketJob::Sliced::Slice::ROWS_GUARD, document["r"]
          assert_equal rows.to_h, document["s"]
        end
      end
    end
  end
end

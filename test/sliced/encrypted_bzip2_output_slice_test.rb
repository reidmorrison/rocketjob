require_relative "../test_helper"

module Sliced
  class EncryptedBZip2OutputSliceTest < Minitest::Test
    describe RocketJob::Sliced::EncryptedBZip2OutputSlice do
      let :collection_name do
        :slice_test_specific
      end

      let :slices do
        RocketJob::Sliced::EncryptedBZip2OutputSlice.with_collection(collection_name)
      end

      let :slice do
        RocketJob::Sliced::EncryptedBZip2OutputSlice.new(collection_name: collection_name)
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
        it "Decrypts without decompressing" do
          data = SymmetricEncryption.cipher.binary_encrypt(compressed_dataset, random_iv: true, compress: true)

          slice_with_records.attributes["records"] = BSON::Binary.new(data)

          result = slice_with_records.send(:parse_records)

          assert_equal [compressed_dataset], result
          assert_equal [compressed_dataset], slice_with_records.records
        end
      end

      describe "#serialize_records" do
        it "Encrypts and compresses the records" do
          result = slice_with_records.send(:serialize_records)

          assert_kind_of BSON::Binary, result

          encrypted_str = result.data

          header = SymmetricEncryption::Header.new
          header.parse(encrypted_str)
          # Use the header that is present to decrypt the data, since its version could be different
          decrypted_str = header.cipher.binary_decrypt(encrypted_str, header: header)

          assert_equal compressed_dataset, decrypted_str
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
          assert_equal [compressed_dataset], found_slice.to_a
        end

        it "updates existing record" do
          assert slice_with_records.start!
          assert slice_with_records.complete!
          assert found_slice = slices.find(slice_with_records.id)
          assert_equal [compressed_dataset], found_slice.to_a
        end
      end

      # Returns [String] the text of the supplied compressed records, which can hold more than one BZip2 stream.
      def decompress(data)
        IOStreams::Bzip2::Reader.stream(StringIO.new(data), &:read)
      end

      describe "#append_records" do
        it "appends to the records of a new slice" do
          slice << "hello"
          slice.append_records(["world"])

          assert_equal %w[hello world], slice.to_a
        end

        it "compresses the records appended to a slice that was read back after its compressed records" do
          slice << "hello"
          slice.save!
          found_slice = slices.find(slice.id)
          found_slice.append_records(%w[world again])
          found_slice.save!

          assert_equal "hello\nworld\nagain\n", decompress(slices.find(slice.id).records.first)
        end

        it "writes the records appended to a slice that was read back in its text encoding" do
          slice.text_encoding = "ISO-8859-1"
          slice << "José"
          slice.save!
          found_slice = slices.find(slice.id)

          assert_equal "ISO-8859-1", found_slice.text_encoding

          found_slice.append_records(["Zürich"])
          found_slice.save!

          assert_equal "Jos\xE9\nZ\xFCrich\n".b, decompress(slices.find(slice.id).records.first).b
        end
      end

      it "keeps the compressed records of a slice that was read back when it is saved again" do
        slice << "hello"
        slice.save!
        found_slice = slices.find(slice.id)
        found_slice.start!

        assert_equal "hello\n", decompress(slices.find(slice.id).records.first)
      end
    end
  end
end

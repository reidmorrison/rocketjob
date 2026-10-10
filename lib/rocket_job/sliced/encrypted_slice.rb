require "symmetric-encryption"
module RocketJob
  module Sliced
    # Compress the records within a slice
    class EncryptedSlice < ::RocketJob::Sliced::Slice
      private

      def parse_records
        # A slice without records is saved as an empty array, see #serialize_records
        binary = attributes.delete("records")
        return @records = [] unless binary.is_a?(BSON::Binary)

        # Convert BSON::Binary to a string
        encrypted_str = binary.data

        header = SymmetricEncryption::Header.new
        header.parse(encrypted_str)
        # Use the header that is present to decrypt the data, since its version could be different
        decrypted_str = header.cipher.binary_decrypt(encrypted_str, header: header)

        @records = Hash.from_bson(BSON::ByteBuffer.new(decrypted_str))["r"]
      end

      def serialize_records
        return [] if @records.nil? || @records.empty?

        # Convert slice of records into a single string
        str = {"r" => to_a}.to_bson.to_s

        # Encrypt to binary without applying an encoding such as Base64
        # Use a random_iv with each encryption for better security
        data = SymmetricEncryption.cipher.binary_encrypt(str, random_iv: true, compress: true)
        BSON::Binary.new(data)
      end
    end
  end
end

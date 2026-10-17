module RocketJob
  module Sliced
    # Compress and encrypt the records within a slice, see Sliced::Encryption.
    class EncryptedSlice < ::RocketJob::Sliced::BinarySlice
      private

      def encode_records(bson)
        Encryption.encrypt(bson, compress: true)
      end

      def decode_records(data)
        Encryption.decrypt(data)
      end
    end
  end
end

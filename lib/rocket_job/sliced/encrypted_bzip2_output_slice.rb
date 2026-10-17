module RocketJob
  module Sliced
    # This is a specialized output serializer that renders each output slice as a single BZip2 compressed stream,
    # as BZip2OutputSlice does, which is encrypted when it is saved.
    #
    # Each slice is decrypted when it is read, so that its compressed records are downloaded as they are, for
    # example after a header line written by .to_binary, which is not encrypted.
    class EncryptedBZip2OutputSlice < ::RocketJob::Sliced::BZip2OutputSlice
      private

      # Decrypts the supplied saved data, see Sliced::Encryption.
      def read_binary(encrypted)
        Encryption.decrypt(encrypted)
      end

      # Encrypts the compressed records, without compressing them again, see Sliced::Encryption.
      def write_binary(compressed)
        Encryption.encrypt(compressed, compress: false)
      end
    end
  end
end

module RocketJob
  module Sliced
    # This is a specialized output serializer that renders each output slice as a single BZip2 compressed stream,
    # as BZip2OutputSlice does, which is encrypted when it is saved.
    #
    # Each slice is decrypted when it is read, so that its compressed records are downloaded as they are, for
    # example after a header line written by .to_binary, which is not encrypted.
    class EncryptedBZip2OutputSlice < ::RocketJob::Sliced::BZip2OutputSlice
      private

      # Decrypts the supplied saved data.
      def read_binary(encrypted_str)
        header = SymmetricEncryption::Header.new
        header.parse(encrypted_str)
        # Use the header that is present to decrypt the data, since its version could be different
        header.cipher.binary_decrypt(encrypted_str, header: header)
      end

      # Encrypt to binary without applying an encoding such as Base64
      # Use a random_iv with each encryption for better security
      def write_binary(compressed)
        SymmetricEncryption.cipher.binary_encrypt(compressed, random_iv: true, compress: false)
      end
    end
  end
end

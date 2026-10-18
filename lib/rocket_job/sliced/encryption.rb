require "symmetric-encryption"
module RocketJob
  module Sliced
    # How the records of an encrypted slice are encrypted with Symmetric Encryption, see EncryptedSlice and
    # EncryptedBZip2OutputSlice.
    module Encryption
      # Returns [String] the supplied data encrypted to binary, without an encoding such as Base64, with a random
      # initialization vector each time, for better security, and compressed first when `compress` is true.
      def self.encrypt(data, compress:)
        SymmetricEncryption.cipher.binary_encrypt(data, random_iv: true, compress: compress)
      end

      # Returns [String] the supplied data decrypted, see .encrypt, with the cipher that its header names, since the
      # data can have been encrypted with an earlier version of the key.
      def self.decrypt(encrypted)
        header = SymmetricEncryption::Header.new
        header.parse(encrypted)
        header.cipher.binary_decrypt(encrypted, header: header)
      end
    end
  end
end

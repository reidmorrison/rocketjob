module RocketJob
  module Sliced
    # This is a specialized output serializer that renders each output slice as a single BZip2 compressed stream.
    # BZip2 allows multiple output streams to be written into a single BZip2 file.
    #
    # Notes:
    # * The `bzip2` linux command line utility supports multiple embedded BZip2 stream,
    #   but some other custom implementations may not. They may only read the first slice and stop.
    # * It is only designed for use on output collections.
    class EncryptedBZip2OutputSlice < ::RocketJob::Sliced::Slice
      # This is a specialized binary slice for creating BZip2 binary data from each slice
      # that must be downloaded as-is into output files.
      def self.binary_format
        :bz2
      end

      # Compress the supplied records with BZip2, as BZip2OutputSlice does, see BZip2OutputSlice.to_binary.
      # Not encrypted, since each slice is decrypted when it is read, so that its compressed records are downloaded
      # as they are, for example after a header line written by this method.
      def self.to_binary(records, record_delimiter = "\n", encoding: nil)
        BZip2OutputSlice.to_binary(records, record_delimiter, encoding: encoding)
      end

      # The encoding of the text of the records, which is not saved, see BZip2OutputSlice.to_binary.
      attr_accessor :text_encoding

      private

      # Returns [Hash] the BZip2 compressed binary data in binary form when reading back from Mongo.
      def parse_records
        # Convert BSON::Binary to a string
        encrypted_str = attributes.delete("records").data

        # Decrypt string
        header = SymmetricEncryption::Header.new
        header.parse(encrypted_str)
        # Use the header that is present to decrypt the data, since its version could be different
        decrypted_str = header.cipher.binary_decrypt(encrypted_str, header: header)

        @records = [decrypted_str]
      end

      # Returns [BSON::Binary] the records compressed using BZip2 into a string.
      def serialize_records
        return [] if @records.nil? || @records.empty?

        # TODO: Make the line terminator configurable
        compressed = self.class.to_binary(records.to_a, encoding: text_encoding)

        # Encrypt to binary without applying an encoding such as Base64
        # Use a random_iv with each encryption for better security
        data = SymmetricEncryption.cipher.binary_encrypt(compressed, random_iv: true, compress: false)
        BSON::Binary.new(data)
      end
    end
  end
end

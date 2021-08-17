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
        lines = records.to_a.join("\n") + "\n"
        s     = StringIO.new
        IOStreams::Bzip2::Writer.stream(s) { |io| io.write(lines) }

        # Encrypt to binary without applying an encoding such as Base64
        # Use a random_iv with each encryption for better security
        data = SymmetricEncryption.cipher.binary_encrypt(s.string, random_iv: true, compress: false)
        BSON::Binary.new(data)
      end
    end
  end
end

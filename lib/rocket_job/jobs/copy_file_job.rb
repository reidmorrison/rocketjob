# Copy the source_url file/url/path to the target file/url/path.
#
# Example: Upload a file to an SFTP Server:
#
# RocketJob::Jobs::CopyFileJob.create!(
#   source_url:  "/exports/uploads/important.csv.pgp",
#   target_url:  "sftp://sftp.example.org/uploads/important.csv.pgp",
#   target_args: {
#     username: "Jack",
#     password: "OpenSesame",
#     ssh_options: {
#       IdentityFile: "~/.ssh/secondary"
#     }
#   }
# )
#
# Notes:
# - The password is only encrypted when the Symmetric Encryption gem has been installed.
# - If `decrypt: true` then the file will be decrypted with Symmetric Encryption,
#   prior to uploading to the sftp server.
module RocketJob
  module Jobs
    class CopyFileJob < RocketJob::Job
      include RocketJob::Plugins::Retry

      self.destroy_on_complete = false
      # Number of times to automatically retry the copy. Set to `0` for no retry attempts.
      self.retry_limit = 10
      self.priority = 30

      # File names in IOStreams URL format.
      field :source_url, type: String, user_editable: true, path: true
      field :target_url, type: String, user_editable: true, path: true

      # Any optional arguments to pass through to the IOStreams source and/or target.
      field :source_args, type: Hash, default: -> { {} }, user_editable: true
      field :target_args, type: Hash, default: -> { {} }, user_editable: true

      # Any optional IOStreams streams to apply to the source and/or target.
      field :source_streams, type: Hash, default: -> { {none: nil} }, user_editable: true
      field :target_streams, type: Hash, default: -> { {none: nil} }, user_editable: true

      # The encoding of the text in the source and in the target, such as "Windows-1252", to convert the text of the
      # file from one to the other. When only one is set, the other is UTF-8. When neither is set, which is the
      # default, the file is copied byte for byte.
      #
      # Example: Copy a file that Excel saved in Windows-1252 to a partner who requires UTF-8:
      #   RocketJob::Jobs::CopyFileJob.create!(
      #     source_url:      "/exports/prices.csv",
      #     source_encoding: "Windows-1252",
      #     target_url:      "sftp://sftp.example.org/uploads/prices.csv"
      #   )
      field :source_encoding, type: String, user_editable: true
      field :target_encoding, type: String, user_editable: true
      validates_with EncodingValidator, attributes: %i[source_encoding target_encoding]

      # Data to upload, instead of supplying `:input_file_name` above.
      # Note: Data must be less than 15MB after compression.
      if defined?(SymmetricEncryption)
        field :encrypted_source_data, type: String, encrypted: {random_iv: true, compress: true}
      else
        field :source_data, type: String
      end

      validates_presence_of :source_url, unless: :source_data
      validates_presence_of :target_url
      validates_presence_of :source_data, unless: :source_url
      validate :source_path_is_valid, if: -> { source_url && path_changed?(:source) }
      validate :target_path_is_valid, if: -> { target_url && path_changed?(:target) }

      before_save :set_description

      def perform
        if source_data
          target_path.write(source_data)
        elsif target_url
          target_path.copy_from(source_path)
        end

        self.percent_complete = 100
      end

      def source_path
        source = IOStreams.path(source_url, **decode_args(source_args))
        apply_streams(source, source_streams)
        source.encoding(text_encoding(source_encoding)) if converts_text?
        source
      end

      def target_path
        target = IOStreams.path(target_url, **decode_args(target_args))
        apply_streams(target, target_streams)
        target.encoding(text_encoding(target_encoding)) if converts_text?
        target
      end

      # Returns [Hash] the attributes to show, see RocketJob::Plugins::Job::Model#display_attributes, with the secrets
      # in the arguments and streams of the source and target replaced, such as an SFTP password or a PGP passphrase.
      # IOStreams decides which are secret, from the kind of path of each url.
      def display_attributes
        attrs = super
        %w[source target].each do |side|
          args    = attrs["#{side}_args"]
          streams = attrs["#{side}_streams"]
          attrs["#{side}_args"]    = IOStreams.redact_path_options(self["#{side}_url"].to_s, args) if args.is_a?(Hash)
          attrs["#{side}_streams"] = IOStreams.redact_stream_options(streams) if streams.is_a?(Hash)
        end
        attrs
      end

      private

      # Whether the copy converts the text of the file, see #source_encoding, rather than copying its bytes.
      def converts_text?
        source_encoding.present? || target_encoding.present?
      end

      # Returns [String] the encoding of the encode stream that reads or writes text in the supplied encoding,
      # or UTF-8, as the UTF-8 that is copied between them.
      def text_encoding(encoding)
        encoding.present? ? "#{encoding}:UTF-8" : "UTF-8"
      end

      def source_path_is_valid
        validate_path(:source)
      end

      def target_path_is_valid
        validate_path(:target)
      end

      # Whether the url, arguments or streams of the source or target are new or changed, so that a job whose path
      # was valid when it was created, can still be saved, for example when it fails.
      def path_changed?(side)
        new_record? || %w[url args streams].any? { |name| attribute_changed?("#{side}_#{name}") }
      end

      # Builds the path of the source or target without using it, so that IOStreams checks its url, the names and
      # values of its arguments, and its streams, in the same way as #perform. Encrypted arguments are not decrypted,
      # nor secrets fetched, since their values are not used.
      def validate_path(side)
        url  = public_send("#{side}_url")
        path = IOStreams.path(url, **decode_args(public_send("#{side}_args"), decode: false))
      rescue LoadError
        # A gem that the path needs is not installed in this process, so the path is checked when the job runs.
        nil
      rescue StandardError => e
        # The url is not included in an error message, since it can include credentials.
        if valid_url?(url)
          errors.add(:"#{side}_args", path_error_message(e))
        else
          errors.add(:"#{side}_url", "is not a valid url")
        end
      else
        validate_streams(side, path)
      end

      def validate_streams(side, path)
        apply_streams(path, public_send("#{side}_streams"), decode: false)
      rescue StandardError => e
        errors.add(:"#{side}_streams", path_error_message(e))
      end

      # Whether the url on its own is valid, so that a path that is not valid has arguments that are not.
      def valid_url?(url)
        IOStreams.path(url)
        true
      rescue LoadError
        true
      rescue StandardError
        false
      end

      # The message of an ArgumentError names the argument or stream that is not valid, such as
      # "unknown keyword: :passwrd". Any other error, such as a TypeError from a value of the wrong type, is not
      # shown, since its message can include that value, which can be a secret.
      def path_error_message(exception)
        exception.is_a?(ArgumentError) ? exception.message : "are not valid"
      end

      def set_description
        return if description || target_url.nil?

        # The url can include credentials, which the display name of the path leaves out.
        self.description = "Copying to #{IOStreams.path(target_url).display_name}"
      rescue StandardError
        # The url is not valid, which #perform reports.
        self.description = "Copying file"
      end

      def apply_streams(path, streams, decode: true)
        streams.to_h.each_pair do |stream, args|
          path.stream(stream.to_sym, **decode_args(args, decode: decode))
        end
      end

      # Returns [Hash] the arguments to supply to IOStreams, with the value of each `encrypted_` argument decrypted
      # with Symmetric Encryption, and each `secret_config_` argument fetched from Secret Config, under its name
      # without that prefix. The prefix is kept when its gem is not loaded, so that IOStreams rejects the argument.
      #
      # With `decode: false` the names are the same, but the values are as stored, so that the arguments can be
      # checked without decrypting them or fetching any secrets.
      def decode_args(args, decode: true)
        args.to_h do |key, value|
          name = key.to_s
          if name.start_with?("encrypted_") && defined?(SymmetricEncryption)
            [name.delete_prefix("encrypted_").to_sym, decode ? SymmetricEncryption.decrypt(value) : value]
          elsif name.start_with?("secret_config_") && defined?(SecretConfig)
            [name.delete_prefix("secret_config_").to_sym, decode ? SecretConfig.fetch(value) : value]
          else
            [name.to_sym, value]
          end
        end
      end
    end
  end
end

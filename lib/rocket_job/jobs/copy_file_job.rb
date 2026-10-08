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
        source
      end

      def target_path
        target = IOStreams.path(target_url, **decode_args(target_args))
        apply_streams(target, target_streams)
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

      # Builds the path of the source or target, so that IOStreams checks its url, the names of its arguments and its
      # streams. Encrypted arguments are not decrypted, nor secrets fetched, since their values are not used.
      # The url is not included in an error message, since it can include credentials.
      def validate_path(side)
        url = public_send("#{side}_url")
        begin
          path = IOStreams.path(url)
        rescue StandardError
          errors.add(:"#{side}_url", "is not a valid url")
          return
        end

        begin
          path = IOStreams.path(url, **arg_names(public_send("#{side}_args")))
        rescue ArgumentError => e
          errors.add(:"#{side}_args", e.message)
          return
        end

        public_send("#{side}_streams").each_pair do |stream, args|
          path.stream(stream.to_sym, **(args.nil? ? {} : arg_names(args)))
        end
      rescue ArgumentError => e
        errors.add(:"#{side}_streams", e.message)
      end

      # Returns [Hash] the arguments with the names that #decode_args supplies to IOStreams, and their values as stored.
      def arg_names(args)
        args.to_h { |key, value| [key.to_s.sub(/\A(encrypted|secret_config)_/, "").to_sym, value] }
      end

      def set_description
        return if description || target_url.nil?

        # The url can include credentials, which the display name of the path leaves out.
        self.description = "Copying to #{IOStreams.path(target_url).display_name}"
      rescue StandardError
        # The url is not valid, which #perform reports.
        self.description = "Copying file"
      end

      def apply_streams(path, streams)
        streams.each_pair do |stream, args|
          stream_args = args.nil? ? {} : decode_args(args)
          path.stream(stream.to_sym, **stream_args)
        end
      end

      def decode_args(args)
        return args.symbolize_keys unless defined?(SymmetricEncryption)

        decoded_args = {}
        args.each_pair do |key, value|
          if key.to_s.start_with?("encrypted_") && defined?(SymmetricEncryption)
            original_key               = key.to_s.sub("encrypted_", "").to_sym
            decoded_args[original_key] = SymmetricEncryption.decrypt(value)
          elsif key.to_s.start_with?("secret_config_") && defined?(SecretConfig)
            original_key               = key.to_s.sub("secret_config_", "").to_sym
            decoded_args[original_key] = SecretConfig.fetch(value)
          else
            decoded_args[key.to_sym] = value
          end
        end
        decoded_args
      end
    end
  end
end

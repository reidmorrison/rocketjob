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
      self.retry_limit = 5

      # File names in IOStreams URL format.
      field :source_url, type: String, user_editable: true
      field :target_url, type: String, user_editable: true

      # Any optional arguments to pass through to the IOStreams source and/or target.
      field :source_args, type: Hash, default: -> { {} }
      field :target_args, type: Hash, default: -> { {} }

      # Any optional IOStreams streams to apply to the source and/or target.
      field :source_streams, type: Hash, default: -> { {none: nil} }
      field :target_streams, type: Hash, default: -> { {none: nil} }

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

      before_save :set_description

      def perform
        if source_data
          target_path.write(source_data)
        elsif target_url
          target_path.copy_from(source_path)
        end

        self.percent_complete = 100
      end

      private

      def set_description
        self.description = "Copying to #{target_url}"
      end

      def source_path
        source = IOStreams.path(source_url, **decrypt_args(source_args))
        apply_streams(source, source_streams)
        source
      end

      def target_path
        target = IOStreams.path(target_url, **decrypt_args(target_args))
        apply_streams(target, target_streams)
        target
      end

      def apply_streams(path, streams)
        streams.each_pair { |stream, args| path.stream(stream.to_sym, args.nil? ? {} : decrypt_args(args)) }
      end

      def decrypt_args(args)
        return args.symbolize_keys unless defined?(SymmetricEncryption)

        decrypted_args = {}
        args.each_pair do |key, value|
          if key.to_s.start_with?("encrypted_")
            unencrypted_key                        = key.to_s.sub("encrypted_", "")
            decrypted_args[unencrypted_key.to_sym] = SymmetricEncryption.decrypt(value)
          else
            decrypted_args[key.to_sym] = value
          end
        end
        decrypted_args
      end
    end
  end
end

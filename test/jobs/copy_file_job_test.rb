require_relative "../test_helper"

module Jobs
  class CopyFileJobTest < Minitest::Test
    describe RocketJob::Jobs::CopyFileJob do
      after do
        RocketJob::Jobs::CopyFileJob.delete_all
      end

      def create_job(target_url, **)
        RocketJob::Jobs::CopyFileJob.create!(source_url: "/tmp/source.csv", target_url: target_url, **)
      end

      describe "#display_attributes" do
        it "shows the urls without their credentials" do
          job = RocketJob::Jobs::CopyFileJob.new(
            source_url: "https://user:secret@example.org/exports/source.csv",
            target_url: "sftp://jack:secret@sftp.example.org/uploads/source.csv"
          )
          attrs = job.display_attributes

          assert_equal "https://example.org/exports/source.csv", attrs["source_url"]
          assert_equal "sftp://sftp.example.org/uploads/source.csv", attrs["target_url"]
        end

        it "shows the arguments and streams without their secrets" do
          job = RocketJob::Jobs::CopyFileJob.new(
            source_url:     "s3://bucket/exports/source.csv",
            source_args:    {client: {region: "us-east-1", secret_access_key: "s3-secret"}},
            target_url:     "sftp://sftp.example.org/uploads/source.csv",
            target_args:    {username: "jack", password: "sftp-secret", ssh_options: {"IdentityKey" => "key", "IdentityFile" => "~/.ssh/id"}},
            target_streams: {pgp: {passphrase: "pgp-secret", recipient: "a@b.org"}}
          )
          attrs = job.display_attributes

          assert_equal({"client" => {"region" => "us-east-1", "secret_access_key" => "[FILTERED]"}}, attrs["source_args"].deep_stringify_keys)
          assert_equal(
            {"username" => "jack", "password" => "[FILTERED]", "ssh_options" => {"IdentityKey" => "[FILTERED]", "IdentityFile" => "~/.ssh/id"}},
            attrs["target_args"].deep_stringify_keys
          )
          assert_equal({"pgp" => {"passphrase" => "[FILTERED]", "recipient" => "a@b.org"}}, attrs["target_streams"].deep_stringify_keys)
          assert_equal "sftp-secret", job.target_args[:password]
        end
      end

      describe "#valid?" do
        it "accepts the arguments and streams of each path" do
          job = RocketJob::Jobs::CopyFileJob.new(
            source_url:     "/tmp/source.csv",
            target_url:     "sftp://sftp.example.org/uploads/source.csv",
            target_args:    {username: "jack", encrypted_password: "not-decrypted", ssh_options: {"IdentityFile" => "~/.ssh/id"}},
            target_streams: {pgp: {recipient: "a@b.org"}}
          )

          assert_predicate job, :valid?, job.errors.full_messages
        end

        it "rejects an argument that the path does not accept" do
          job = RocketJob::Jobs::CopyFileJob.new(source_url: "/tmp/source.csv", target_url: "sftp://sftp.example.org/a.csv",
                                                 target_args: {passwrd: "secret"})

          refute_predicate job, :valid?
          assert_includes job.errors[:target_args].first, "passwrd"
        end

        it "rejects a stream option that the stream does not accept" do
          job = RocketJob::Jobs::CopyFileJob.new(source_url: "/tmp/source.csv", target_url: "/tmp/target.csv",
                                                 target_streams: {pgp: {recepient: "a@b.org"}})

          refute_predicate job, :valid?
          assert_includes job.errors[:target_streams].first, "recepient"
        end

        it "rejects a url that is not valid, without including it in the message" do
          job = RocketJob::Jobs::CopyFileJob.new(source_url: "/tmp/source.csv", target_url: "sftp://jack:secret@sftp.example.org:port/a.csv")

          refute_predicate job, :valid?
          assert_equal ["is not a valid url"], job.errors[:target_url]
        end

        it "rejects an argument value of the wrong type, without including it in the message" do
          job = RocketJob::Jobs::CopyFileJob.new(source_url: "/tmp/source.csv", target_url: "sftp://sftp.example.org/a.csv",
                                                 target_args: {ssh_options: "secret"})

          refute_predicate job, :valid?
          assert_equal ["are not valid"], job.errors[:target_args]
        end

        it "rejects a secret_config argument when Secret Config is not loaded, as the job would when it runs" do
          job = RocketJob::Jobs::CopyFileJob.new(source_url: "/tmp/source.csv", target_url: "sftp://sftp.example.org/a.csv",
                                                 target_args: {secret_config_password: "sftp/password"})

          refute_predicate job, :valid?
          assert_includes job.errors[:target_args].first, "secret_config_password"
        end

        it "accepts streams that are not set" do
          job = RocketJob::Jobs::CopyFileJob.new(source_url: "/tmp/source.csv", target_url: "/tmp/target.csv", target_streams: nil)

          assert_predicate job, :valid?, job.errors.full_messages
        end

        it "rejects stream options of the wrong type, without including them in the message" do
          job = RocketJob::Jobs::CopyFileJob.new(source_url: "/tmp/source.csv", target_url: "/tmp/target.csv",
                                                 target_streams: {pgp: "secret"})

          refute_predicate job, :valid?
          assert_equal ["are not valid"], job.errors[:target_streams]
        end

        it "does not check the paths of a saved job whose paths did not change" do
          job = create_job("/tmp/target.csv")
          job.set(target_args: {passwrd: "secret"})
          job.reload

          assert_predicate job, :valid?
        end
      end

      describe "#description" do
        it "names the target without the credentials in its url" do
          job = create_job("sftp://jack:secret@sftp.example.org/uploads/source.csv")

          assert_equal "Copying to sftp://sftp.example.org/uploads/source.csv", job.description
        end

        it "names the target without the query of its url" do
          job = create_job("https://example.org/uploads/source.csv?token=secret")

          assert_equal "Copying to https://example.org/uploads/source.csv", job.description
        end

        it "names an S3 target without loading the AWS SDK" do
          job = create_job("s3://bucket/uploads/source.csv")

          assert_equal "Copying to s3://bucket/uploads/source.csv", job.description
        end

        it "leaves out a target whose url is not valid, such as a job saved without validation" do
          job = RocketJob::Jobs::CopyFileJob.new(source_url: "/tmp/source.csv", target_url: "ftp://jack:secret@ftp.example.org/source.csv")
          job.save!(validate: false)

          assert_equal "Copying file", job.description
        end

        it "keeps a supplied description" do
          job = create_job("sftp://sftp.example.org/uploads/source.csv", description: "Nightly export")

          assert_equal "Nightly export", job.description
        end
      end
    end
  end
end

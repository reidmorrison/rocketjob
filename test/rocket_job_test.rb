require_relative "test_helper"

class RocketJobTest < Minitest::Test
  describe RocketJob do
    describe ".seconds_as_duration" do
      it "returns nil when seconds is nil" do
        assert_nil RocketJob.seconds_as_duration(nil)
      end

      it "formats sub-millisecond durations with three decimals" do
        assert_equal "5.000ms", RocketJob.seconds_as_duration(0.005)
      end

      it "formats larger millisecond durations with one decimal" do
        assert_equal "50.0ms", RocketJob.seconds_as_duration(0.05)
      end

      it "formats durations of at least one second" do
        assert_equal "5.000s", RocketJob.seconds_as_duration(5.0)
      end

      it "formats durations of at least one minute" do
        assert_equal "1m 30s", RocketJob.seconds_as_duration(90.0)
      end

      it "formats durations of at least one hour" do
        assert_equal "1h 1m", RocketJob.seconds_as_duration(3661.0)
      end

      it "formats durations of at least one day" do
        # 1 day + 1 hour + 1 minute + 1 second
        assert_equal "1d 1h 1m", RocketJob.seconds_as_duration(90_061.0)
      end
    end

    describe ".valid_utf8" do
      it "returns valid UTF-8 as is" do
        assert_equal "José", RocketJob.valid_utf8("José")
      end

      it "shows each byte that is not valid UTF-8 as \\xHH" do
        assert_equal "caf\\xE9.csv", RocketJob.valid_utf8("caf\xE9.csv")
      end

      it "reads a binary string as UTF-8" do
        text = RocketJob.valid_utf8("José".b)

        assert_equal "José", text
        assert_equal Encoding::UTF_8, text.encoding
        assert_equal "caf\\xE9", RocketJob.valid_utf8("caf\xE9".b)
      end

      it "converts a string in another encoding to UTF-8" do
        assert_equal "café", RocketJob.valid_utf8("caf\xE9".dup.force_encoding(Encoding::ISO_8859_1))
        # 0x81 has no character in Windows-1252.
        assert_equal "a\\x81b", RocketJob.valid_utf8("a\x81b".dup.force_encoding(Encoding::Windows_1252))
      end

      it "returns an empty string for nil" do
        assert_equal "", RocketJob.valid_utf8(nil)
      end

      it "shows each byte that is not valid in an encoding that ASCII is not part of" do
        # "a" followed by the first byte of a character, in UTF-16LE.
        text = "a\x00\xD8".b.force_encoding(Encoding::UTF_16LE)

        assert_equal "a\\xD8", RocketJob.valid_utf8(text)
      end

      it "reads a string in an encoding that Ruby cannot convert as UTF-8" do
        assert_equal "caf\\xE9", RocketJob.valid_utf8("caf\xE9".b.force_encoding(Encoding::UTF_7))
      end

      it "replaces each byte that is not valid with the supplied replacement" do
        assert_equal "caf�.csv", RocketJob.valid_utf8("caf\xE9.csv", replacement: "�")
        assert_equal "caf�.csv", RocketJob.valid_utf8("caf\xE9.csv".b, replacement: "�")
        assert_equal "a�b", RocketJob.valid_utf8("a\x81b".b.force_encoding(Encoding::Windows_1252), replacement: "�")
      end
    end

    describe ".path_display_name" do
      it "returns a local path as is" do
        assert_equal "/var/sftp/in/file.csv", RocketJob.path_display_name("/var/sftp/in/file.csv")
      end

      it "leaves out the credentials of a url" do
        assert_equal "sftp://sftp.example.org/in/file.csv",
                     RocketJob.path_display_name("sftp://user:secret@sftp.example.org/in/file.csv?password=other")
      end

      it "accepts an IOStreams::Path" do
        path = IOStreams.path("sftp://user:secret@sftp.example.org/in/file.csv")

        assert_equal "sftp://sftp.example.org/in/file.csv", RocketJob.path_display_name(path)
      end

      it "returns valid UTF-8 for a name that SFTP lists as binary, or that is not valid UTF-8" do
        directory = IOStreams.path("sftp://user:secret@sftp.example.org/in")

        assert_equal "sftp://sftp.example.org/in/café.csv", RocketJob.path_display_name(directory.join("café.csv".b))
        assert_equal "sftp://sftp.example.org/in/caf\\xE9.csv", RocketJob.path_display_name(directory.join("caf\xE9.csv".b))
      end

      it "leaves out a password that holds an @" do
        assert_equal "sftp://sftp.example.org/in/file.csv",
                     RocketJob.path_display_name("sftp://user:p@ss@sftp.example.org/in/file.csv")
      end

      it "leaves out a path that is not valid, since its credentials cannot be found" do
        assert_equal RocketJob::INVALID_PATH_DISPLAY_NAME,
                     RocketJob.path_display_name("sftp://user:secret@sftp.example.org:port/in/file.csv")
      end

      it "leaves out a path that needs a gem that is not installed" do
        IOStreams.stub(:path, ->(_path) { raise LoadError, "cannot load such file -- aws-sdk-s3" }) do
          assert_equal RocketJob::INVALID_PATH_DISPLAY_NAME, RocketJob.path_display_name("s3://bucket/in/file.csv")
        end
      end

      it "returns a blank path as is" do
        assert_nil RocketJob.path_display_name(nil)
        assert_equal "", RocketJob.path_display_name("")
      end
    end

    describe "process flags" do
      before do
        @server = RocketJob.instance_variable_get(:@server)
        @rails  = RocketJob.instance_variable_get(:@rails)
      end

      after do
        RocketJob.instance_variable_set(:@server, @server)
        RocketJob.instance_variable_set(:@rails, @rails)
      end

      it "tracks the server flag" do
        RocketJob.instance_variable_set(:@server, false)

        refute_predicate RocketJob, :server?
        RocketJob.server!

        assert_predicate RocketJob, :server?
      end

      it "tracks the rails flag and standalone is its inverse" do
        RocketJob.instance_variable_set(:@rails, false)

        refute_predicate RocketJob, :rails?
        assert_predicate RocketJob, :standalone?

        RocketJob.rails!

        assert_predicate RocketJob, :rails?
        refute_predicate RocketJob, :standalone?
      end
    end
  end
end

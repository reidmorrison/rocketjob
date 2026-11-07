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

    describe ".path_display_name" do
      # Returns [Array<String>] the deprecation warnings that IOStreams reported while the block runs, with deprecation
      # warnings on, so that the tests do not print them.
      def iostreams_deprecation_warnings(&block)
        warnings = []
        previous = Warning[:deprecated]
        Warning[:deprecated] = true
        collect = lambda do |message, category: nil|
          warnings << message if category == :deprecated && IOStreams::Deprecation.warning?(message)
        end
        Warning.stub(:warn, collect, &block)
        warnings
      ensure
        Warning[:deprecated] = previous
      end

      it "returns a local path as is" do
        assert_equal "/var/sftp/in/file.csv", RocketJob.path_display_name("/var/sftp/in/file.csv")
      end

      it "leaves out the credentials of a url" do
        assert_equal "sftp://sftp.example.org/in/file.csv",
                     RocketJob.path_display_name("sftp://user:secret@sftp.example.org/in/file.csv")
      end

      it "leaves out the query of a url, which can hold a secret" do
        warnings = iostreams_deprecation_warnings do
          assert_equal "sftp://sftp.example.org/in/file.csv",
                       RocketJob.path_display_name("sftp://user:secret@sftp.example.org/in/file.csv?password=other")
        end

        assert_equal 1, warnings.size, warnings
        assert_includes warnings.first, "its query is ignored"
        refute_includes warnings.first, "secret"
      end

      it "accepts an IOStreams::Path" do
        path = IOStreams.path("sftp://user:secret@sftp.example.org/in/file.csv")

        assert_equal "sftp://sftp.example.org/in/file.csv", RocketJob.path_display_name(path)
      end

      it "leaves out a path that is not valid, since its credentials cannot be found" do
        assert_equal RocketJob::INVALID_PATH_DISPLAY_NAME,
                     RocketJob.path_display_name("sftp://user:secret@sftp.example.org:port/in/file.csv")
      end

      [
        "sftp://sftp.example.org/in/données.csv",
        "sftp://sftp.example.org/in/data[1].csv",
        "sftp://sftp.example.org/in/{a}%^|\"<b>.csv"
      ].each do |url|
        it "shows a url that is not a valid path as stored, when it holds no credentials: #{url}" do
          assert_equal url, RocketJob.path_display_name(url)
        end
      end

      it "shows a url that is not a valid path as valid UTF-8, when it holds no credentials" do
        name = RocketJob.path_display_name("sftp://sftp.example.org/in/caf\xE9.csv".b)

        assert_equal "sftp://sftp.example.org/in/caf\\xE9.csv", name
        assert_predicate name, :valid_encoding?
      end

      it "shows a url that needs a gem that is not installed as stored, when it holds no credentials" do
        IOStreams.stub(:path, ->(_path) { raise LoadError, "cannot load such file -- aws-sdk-s3" }) do
          assert_equal "s3://bucket/in/file.csv", RocketJob.path_display_name("s3://bucket/in/file.csv")
        end
      end

      [
        "sftp://user:pa/ss@sftp.example.org/in/file.csv",
        "sftp://user:pa#ss@sftp.example.org/in/file.csv",
        "sftp://user:secret@sftp.example.org/in/données.csv",
        "sftp://sftp.example.org/in/données.csv?password=secret"
      ].each do |url|
        it "leaves out a url that is not a valid path, with a user name and password or a query: #{url}" do
          assert_equal RocketJob::INVALID_PATH_DISPLAY_NAME, RocketJob.path_display_name(url)
        end
      end

      it "leaves out a url that needs a gem that is not installed, with a user name and password or a query" do
        IOStreams.stub(:path, ->(_path) { raise LoadError, "cannot load such file -- aws-sdk-s3" }) do
          assert_equal RocketJob::INVALID_PATH_DISPLAY_NAME, RocketJob.path_display_name("s3://key:secret@bucket/in/file.csv")
          assert_equal RocketJob::INVALID_PATH_DISPLAY_NAME,
                       RocketJob.path_display_name("s3://bucket/in/file.csv?secret_access_key=secret")
        end
      end

      it "returns a blank path as is" do
        assert_nil RocketJob.path_display_name(nil)
        assert_equal "", RocketJob.path_display_name("")
      end
    end

    describe ".display_text" do
      it "returns valid UTF-8 text as is" do
        assert_equal "données.csv", RocketJob.display_text("données.csv")
      end

      it "shows each byte that is not valid UTF-8 as \\xHH" do
        text = RocketJob.display_text("caf\xE9.csv".b)

        assert_equal "caf\\xE9.csv", text
        assert_equal Encoding::UTF_8, text.encoding
        assert_predicate text, :valid_encoding?
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

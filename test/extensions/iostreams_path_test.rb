require_relative "../test_helper"

module Extensions
  class IOStreamsPathTest < Minitest::Test
    describe IOStreams::Path do
      describe ".invalid_url?" do
        it "is true for a url whose scheme IOStreams does not know, or that it cannot parse" do
          assert IOStreams::Path.invalid_url?("s4://bucket/in/data.csv")
          assert IOStreams::Path.invalid_url?("http://[bad/data.csv")
        end

        it "is false for a path or url that IOStreams can make a path of" do
          refute IOStreams::Path.invalid_url?("/var/sftp/in/data.csv")
          refute IOStreams::Path.invalid_url?("sftp://sftp.example.org/in/data.csv")
        end

        it "is false for a url whose scheme needs a gem that is not loaded" do
          IOStreams.stub(:path, ->(*) { raise(LoadError, "Please install the gem 'aws-sdk-s3' to support AWS S3.") }) do
            refute IOStreams::Path.invalid_url?("s3://bucket/in/data.csv")
          end
        end
      end

      describe ".demongoize" do
        it "returns nil for nil" do
          assert_nil IOStreams::Path.demongoize(nil)
        end

        it "returns the path of a stored url" do
          path = IOStreams::Path.demongoize("sftp://sftp.example.org/in/data.csv")

          assert_kind_of IOStreams::Paths::SFTP, path
          assert_equal "/in/data.csv", path.path
        end

        it "returns a stored url whose scheme IOStreams does not know as stored, which raises when it is used as a path" do
          url = "foo://host/in/data.csv"

          assert_equal url, IOStreams::Path.demongoize(url)
          assert_raises(ArgumentError) { IOStreams.new(IOStreams::Path.demongoize(url)) }
        end

        it "returns a stored url whose scheme needs a gem that is not loaded as stored" do
          url = "s3://bucket/in/data.csv"

          IOStreams.stub(:path, ->(*) { raise(LoadError, "Please install the gem 'aws-sdk-s3' to support AWS S3.") }) do
            assert_equal url, IOStreams::Path.demongoize(url)
          end
        end

        it "returns a stored url whose scheme IOStreams does not know from a field of type IOStreams::Path, whose extensions can be read" do
          category           = RocketJob::Category::Input.new
          category.file_name = "foo://host/in/data.csv"

          assert_equal "foo://host/in/data.csv", category.file_name
          assert_equal RocketJob::INVALID_PATH_DISPLAY_NAME, RocketJob.path_display_name(category.file_name)
          assert_equal :csv, category.tabular.format
        end

        it "raises what IOStreams raises when a category of format :auto asks a stored url that it cannot read for its format" do
          job                          = RocketJob::Jobs::OnDemandBatchJob.new(code: "row")
          job.input_category.format    = :auto
          job.input_category.file_name = "foo://host/in/data.csv"

          error = assert_raises(ArgumentError) { job.upload { |records| records << "a,b" } }
          assert_match(/Unknown Scheme type/, error.message)
        end
      end
    end
  end
end

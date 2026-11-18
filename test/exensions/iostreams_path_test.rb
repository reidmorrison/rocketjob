require_relative "../test_helper"

module Extensions
  class IOStreamsPathTest < Minitest::Test
    describe IOStreams::Path do
      describe ".demongoize" do
        it "returns nil for nil" do
          assert_nil IOStreams::Path.demongoize(nil)
        end

        it "returns the path of a stored file name" do
          path = IOStreams::Path.demongoize("/var/sftp/in/données.csv")

          assert_kind_of IOStreams::Paths::File, path
          assert_equal "/var/sftp/in/données.csv", path.to_s
        end

        it "returns the path of a stored url" do
          path = IOStreams::Path.demongoize("sftp://sftp.example.org/in/donn%C3%A9es.csv")

          assert_kind_of IOStreams::Paths::SFTP, path
          assert_equal "/in/données.csv", path.path
        end

        it "returns a stored url that IOStreams cannot parse as stored, which raises when it is used as a path" do
          url = "sftp://sftp.example.org/in/données.csv"

          assert_equal url, IOStreams::Path.demongoize(url)
          assert_raises(URI::InvalidURIError) { IOStreams.new(IOStreams::Path.demongoize(url)) }
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

        it "returns a stored url whose scheme needs a gem that is not loaded from a field of type IOStreams::Path, whose extensions can be read" do
          category = RocketJob::Category::Input.new(file_name: "s3://bucket/in/data.csv")
          IOStreams.stub(:path, ->(*) { raise(LoadError, "Please install the gem 'aws-sdk-s3' to support AWS S3.") }) do
            assert_equal "s3://bucket/in/data.csv", category.file_name
            assert_equal "s3://bucket/in/data.csv", RocketJob.path_display_name(category.file_name)
            assert_equal :csv, category.tabular.format
          end
        end

        it "lets a category whose file name needs a gem that is not loaded propose a schema" do
          category = RocketJob::Category::Input.new(file_name: "s3://bucket/in/data.csv", format: :auto, columns: %w[a b])
          IOStreams.stub(:path, ->(*) { raise(LoadError, "Please install the gem 'aws-sdk-s3' to support AWS S3.") }) do
            proposal = category.schema_proposal("ImportJob, input category main", defined: RocketJob::Category::Input.new)

            assert_nil proposal.error
            assert_equal({"columns" => nil}, proposal.changes)
          end
        end

        it "returns a stored url that IOStreams cannot parse from a field of type IOStreams::Path, whose extensions can be read" do
          category = RocketJob::Category::Input.new
          category.file_name = "sftp://sftp.example.org/in/data[1].csv"

          assert_equal "sftp://sftp.example.org/in/data[1].csv", category.file_name
          assert_equal :csv, category.tabular.format
        end
      end
    end
  end
end

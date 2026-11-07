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

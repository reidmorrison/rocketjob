require_relative "../test_helper"

module Extensions
  class YamlTest < Minitest::Test
    describe IOStreams::Path do
      describe "serializes yaml" do
        it "to string" do
          url  = "http://localhost/path/file_name.zip"
          path = IOStreams.path(url)
          assert_equal "--- #{url}\n", Psych.dump(path)
        end
      end
    end
  end
end

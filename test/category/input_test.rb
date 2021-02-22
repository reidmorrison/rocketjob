require_relative "../test_helper"

module Batch
  class CategoryTest < Minitest::Test
    describe RocketJob::Category::Input do
      let(:mongoized) { { "name" => "blah", "serializer" => "encrypt", "file_name" => "MyFile.txt", "columns" => ["abc", "def"], "format" => "psv", "format_options" => { "blah" => 23 }, "mode" => "array" } }

      describe "initialize" do
        it "converts string arguments" do
          category = RocketJob::Category::Input.new(
            name:           "blah",
            serializer:     "compress",
            file_name:      "MyFile.txt",
            columns:        ["abc", "def"],
            format:         "csv",
            format_options: { "blah" => 23 },
            mode:           "line"
          )
          assert_equal :blah, category.name
          assert_equal :compress, category.serializer
          assert_equal "MyFile.txt", category.file_name
          assert_equal(["abc", "def"], category.columns)
          assert_equal :csv, category.format
          assert_equal({ blah: 23 }, category.format_options)
          assert_equal :line, category.mode
        end

        it "accepts symbol arguments" do
          category = RocketJob::Category::Input.new(
            name:           "blah",
            serializer:     :encrypt,
            file_name:      "MyFile.txt",
            columns:        [:abc, :def],
            format:         :psv,
            format_options: { blah: 23 },
            mode:           :array
          )
          assert_equal :blah, category.name
          assert_equal :encrypt, category.serializer
          assert_equal "MyFile.txt", category.file_name
          assert_equal(["abc", "def"], category.columns)
          assert_equal :psv, category.format
          assert_equal({ blah: 23 }, category.format_options)
          assert_equal :array, category.mode
        end

        it "accepts string keys" do
          category = RocketJob::Category::Input.new(**mongoized.symbolize_keys)
          assert_equal :blah, category.name
          assert_equal :encrypt, category.serializer
          assert_equal "MyFile.txt", category.file_name
          assert_equal(["abc", "def"], category.columns)
          assert_equal :psv, category.format
          assert_equal({ blah: 23 }, category.format_options)
          assert_equal :array, category.mode
        end

        it "rejects bad serializers" do
          assert_raises ArgumentError do
            RocketJob::Category::Input.new(name: :blah, serializer: :blah)
          end
        end
      end

      describe "serializer_class" do
        let(:category) { RocketJob::Category::Input.new(name: :blah) }

        it "uses default none" do
          assert_equal RocketJob::Sliced::Slice, category.serializer_class
        end

        it "uses default encrypt" do
          assert_equal RocketJob::Sliced::EncryptedSlice, category.serializer_class(default_encrypt: true, default_compress: true)
        end

        it "uses default compress" do
          assert_equal RocketJob::Sliced::CompressedSlice, category.serializer_class(default_encrypt: false, default_compress: true)
        end

        it "compress" do
          category = RocketJob::Category::Input.new(name: :blah, serializer: :compress)
          assert_equal RocketJob::Sliced::CompressedSlice, category.serializer_class(default_encrypt: false, default_compress: false)
        end

        it "encrypt" do
          category = RocketJob::Category::Input.new(name: :blah, serializer: :encrypt)
          assert_equal RocketJob::Sliced::EncryptedSlice, category.serializer_class(default_encrypt: false, default_compress: false)
        end

        it "bzip2" do
          category = RocketJob::Category::Input.new(name: :blah, serializer: :bzip2)
          assert_equal RocketJob::Sliced::BZip2OutputSlice, category.serializer_class(default_encrypt: false, default_compress: false)
        end
      end

      describe "mongoize" do
        it "serializes" do
          category = RocketJob::Category::Input.new(
            name:           "blah",
            serializer:     :encrypt,
            file_name:      "MyFile.txt",
            columns:        [:abc, :def],
            format:         :psv,
            format_options: { blah: 23 },
            mode:           :array
          )
          assert_equal mongoized, category.mongoize
        end
      end
    end
  end
end

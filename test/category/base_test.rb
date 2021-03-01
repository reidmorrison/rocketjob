require_relative "../test_helper"

module Batch
  class CategoryTest < Minitest::Test
    describe RocketJob::Category::Base do
      let(:mongoized) { {"name" => "blah", "serializer" => "encrypt", "file_name" => "MyFile.txt", "columns" => ["abc", "def"], "format" => "psv", "format_options" => {"blah" => 23}} }

      describe "initialize" do
        it "converts string arguments" do
          category = RocketJob::Category::Base.new(
            name:           "blah",
            serializer:     "compress",
            file_name:      "MyFile.txt",
            columns:        ["abc", "def"],
            format:         "csv",
            format_options: {"blah" => 23}
          )
          assert_equal :blah, category.name
          assert_equal :compress, category.serializer
          assert_equal "MyFile.txt", category.file_name.to_s
          assert_equal(["abc", "def"], category.columns)
          assert_equal :csv, category.format
          assert_equal({blah: 23}, category.format_options)
        end

        it "accepts symbol arguments" do
          category = RocketJob::Category::Base.new(
            name:           :blah,
            serializer:     :encrypt,
            file_name:      "MyFile.txt",
            columns:        [:abc, :def],
            format:         :psv,
            format_options: {blah: 23}
          )
          assert_equal :blah, category.name
          assert_equal :encrypt, category.serializer
          assert_equal "MyFile.txt", category.file_name.to_s
          assert_equal(["abc", "def"], category.columns)
          assert_equal :psv, category.format
          assert_equal({blah: 23}, category.format_options)
        end

        it "defaults to main category" do
          category = RocketJob::Category::Base.new
          assert_equal :main, category.name
        end

        it "accepts string keys" do
          category = RocketJob::Category::Base.new(**mongoized.symbolize_keys)
          assert_equal :blah, category.name
          assert_equal :encrypt, category.serializer
          assert_equal "MyFile.txt", category.file_name.to_s
          assert_equal(["abc", "def"], category.columns)
          assert_equal :psv, category.format
          assert_equal({blah: 23}, category.format_options)
        end

        it "rejects bad serializers" do
          assert_raises ArgumentError do
            RocketJob::Category::Base.new(name: :blah, serializer: :blah)
          end
        end
      end

      describe "serializer_class" do
        let(:category) { RocketJob::Category::Base.new(name: :blah) }

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
          category = RocketJob::Category::Base.new(name: :blah, serializer: :compress)
          assert_equal RocketJob::Sliced::CompressedSlice, category.serializer_class(default_encrypt: false, default_compress: false)
        end

        it "encrypt" do
          category = RocketJob::Category::Base.new(name: :blah, serializer: :encrypt)
          assert_equal RocketJob::Sliced::EncryptedSlice, category.serializer_class(default_encrypt: false, default_compress: false)
        end

        it "bzip2" do
          category = RocketJob::Category::Base.new(name: :blah, serializer: :bzip2)
          assert_equal RocketJob::Sliced::BZip2OutputSlice, category.serializer_class(default_encrypt: false, default_compress: false)
        end
      end

      describe "tabular" do
        it "returns tabular for the current settings" do
          layout   = [
            {size: 1, key: :action},
            {size: 9, key: :date},
            {size: :remainder}
          ]
          category = RocketJob::Category::Base.new(
            columns:        %i[abc, def],
            format:         :fixed,
            format_options: {layout: layout}
          )
          assert tabular = category.tabular
          assert_equal %w[abc, def], tabular.header.columns
          assert tabular.parser.is_a?(IOStreams::Tabular::Parser::Fixed), tabular.parser.class.name
          actual = tabular.parser.layout.columns.collect do |col|
            h       = {
              size: col.size == -1 ? :remainder : col.size
            }
            h[:key] = col.key if col.key
            h
          end
          assert_equal layout, actual
        end

        it "uses the file_name when format is not set" do
          category = RocketJob::Category::Base.new(file_name: "sample.json")
          assert tabular = category.tabular
          assert tabular.parser.is_a?(IOStreams::Tabular::Parser::Json), tabular.parser.class.name
        end
      end

      describe "tabular?" do
        it "is tabular when format is set" do
          category = RocketJob::Category::Base.new(format: :psv)
          assert category.tabular?
        end

        it "not tabular when only filename is set" do
          category = RocketJob::Category::Base.new(file_name: "sample.json")
          refute category.tabular?
        end

        it "otherwise not tabular" do
          category = RocketJob::Category::Base.new
          refute category.tabular?
        end
      end

      describe "mongoize" do
        it "serializes" do
          category = RocketJob::Category::Base.new(
            name:           "blah",
            serializer:     :encrypt,
            file_name:      "MyFile.txt",
            columns:        [:abc, :def],
            format:         :psv,
            format_options: {blah: 23}
          )
          assert_equal mongoized, category.mongoize
        end
      end
    end
  end
end

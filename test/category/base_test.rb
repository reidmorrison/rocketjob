require_relative "../test_helper"

module Batch
  class CategoryTest < Minitest::Test
    describe RocketJob::Category::Base do
      describe "#serializer_class" do
        let(:category) { RocketJob::Category::Input.new(name: :blah) }

        it "uses default compress" do
          assert_equal RocketJob::Sliced::CompressedSlice, category.serializer_class
        end

        it "none" do
          category = RocketJob::Category::Input.new(name: :blah, serializer: :none)
          assert_equal RocketJob::Sliced::Slice, category.serializer_class
        end

        it "compress" do
          category = RocketJob::Category::Input.new(name: :blah, serializer: :compress)
          assert_equal RocketJob::Sliced::CompressedSlice, category.serializer_class
        end

        it "encrypt" do
          category = RocketJob::Category::Input.new(name: :blah, serializer: :encrypt)
          assert_equal RocketJob::Sliced::EncryptedSlice, category.serializer_class
        end

        it "bzip2" do
          category = RocketJob::Category::Input.new(name: :blah, serializer: :bzip2)
          assert_equal RocketJob::Sliced::BZip2OutputSlice, category.serializer_class
        end
      end

      describe "tabular" do
        it "returns tabular for the current settings" do
          layout   = [
            {size: 1, key: :action},
            {size: 9, key: :date},
            {size: :remainder}
          ]
          category = RocketJob::Category::Input.new(
            columns:        %w[abc, def],
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
          category = RocketJob::Category::Input.new(file_name: "sample.json")
          assert tabular = category.tabular
          assert tabular.parser.is_a?(IOStreams::Tabular::Parser::Json), tabular.parser.class.name
        end
      end

      describe "tabular?" do
        it "is tabular when format is set" do
          category = RocketJob::Category::Input.new(format: :psv)
          assert category.tabular?
        end

        it "not tabular when only filename is set" do
          category = RocketJob::Category::Input.new(file_name: "sample.json")
          refute category.tabular?
        end

        it "otherwise not tabular" do
          category = RocketJob::Category::Input.new
          refute category.tabular?
        end
      end
    end
  end
end

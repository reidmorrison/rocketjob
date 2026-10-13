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

        it "bz2" do
          category = RocketJob::Category::Input.new(name: :blah, serializer: :bz2)

          assert_equal RocketJob::Sliced::BZip2OutputSlice, category.serializer_class
        end
      end

      describe ".name_in" do
        it "is the name in the properties, or main" do
          assert_equal :other, RocketJob::Category::Input.name_in("name" => "other")
          assert_equal :other, RocketJob::Category::Input.name_in(name: :other)
          assert_equal :main, RocketJob::Category::Input.name_in("slice_size" => 10)
        end
      end

      describe "#merge_properties" do
        it "sets each property" do
          category = RocketJob::Category::Input.new

          assert_same category, category.merge_properties("slice_size" => 10, :encoding => "Windows-1252")
          assert_equal 10, category.slice_size
          assert_equal "Windows-1252", category.encoding
        end
      end

      describe "#property_errors" do
        let(:category) { RocketJob::Category::Input.new }

        it "is empty when the properties are valid" do
          assert_empty category.property_errors("slice_size" => 10, :encoding => "Windows-1252")
        end

        it "names each property that a category does not have" do
          assert_equal ["Unknown property: blah", "Unknown property: nope"],
                       category.property_errors("blah" => 1, :nope => 2, "slice_size" => 10)
        end

        it "returns the errors of a value that is not valid" do
          assert_equal ["Slice size can't be blank"], category.property_errors("slice_size" => nil)
        end

        it "names a property whose value cannot be set, without the value" do
          RocketJob::Category::Input.stub_any_instance(:columns=, ->(_) { raise TypeError, "secret" }) do
            assert_equal ["Columns is not valid"], category.property_errors("columns" => "secret")
          end
        end

        it "does not change the category" do
          category.property_errors("slice_size" => 10)

          assert_equal 100, category.slice_size
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
            columns:        %w[abc def],
            format:         :fixed,
            format_options: {layout: layout}
          )

          assert tabular = category.tabular
          assert_equal %w[abc def], tabular.header.columns
          assert_kind_of IOStreams::Tabular::Parser::Fixed, tabular.parser, tabular.parser.class.name
          # The layout splits each line into its columns.
          assert_equal({action: "A", date: "2026-10-1"}, tabular.parser.parse("A2026-10-1rest"))
        end

        it "uses the file_name when format is not set" do
          category = RocketJob::Category::Input.new(file_name: "sample.json")

          assert tabular = category.tabular
          assert_kind_of IOStreams::Tabular::Parser::Json, tabular.parser, tabular.parser.class.name
        end
      end

      describe "tabular?" do
        it "is tabular when format is set" do
          category = RocketJob::Category::Input.new(format: :psv)

          assert_predicate category, :tabular?
        end

        it "not tabular when only filename is set" do
          category = RocketJob::Category::Input.new(file_name: "sample.json")

          refute_predicate category, :tabular?
        end

        it "otherwise not tabular" do
          category = RocketJob::Category::Input.new

          refute_predicate category, :tabular?
        end
      end
    end
  end
end

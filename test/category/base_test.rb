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

      describe "#schema" do
        let(:schema) { {"fields" => [{"name" => "name", "type" => "string", "width" => 10}]} }

        it "can be a schema" do
          assert_predicate RocketJob::Category::Input.new(schema: schema), :valid?
        end

        it "can be the path or url of a JSON file, which is not read" do
          assert_predicate RocketJob::Category::Input.new(schema: "/does/not/exist/schema.json"), :valid?
          assert_predicate RocketJob::Category::Output.new(schema: "s3://bucket/schema.json"), :valid?
        end

        it "rejects a schema that is not valid" do
          category = RocketJob::Category::Input.new(schema: {"fields" => [{"name" => "name", "type" => "time"}]})

          refute_predicate category, :valid?
          assert_match(/\ASchema is not valid: /, category.errors.full_messages.first)
        end

        it "rejects a value that is neither a schema nor a path" do
          category = RocketJob::Category::Input.new(schema: 12)

          refute_predicate category, :valid?
          assert_equal ["Schema must be a Hash, or the path or url of a JSON file"], category.errors.full_messages
        end

        it "rejects a url that is not valid, without showing it" do
          category = RocketJob::Category::Input.new(schema: "sftp://user:secret@sftp.example.org:port/schema.json")

          refute_predicate category, :valid?
          assert_equal ["Schema is not a valid path or url"], category.errors.full_messages
        end

        it "is shown without the credentials of its url" do
          properties = RocketJob::Category::Input.display_properties("schema" => "sftp://user:secret@host/schema.json")

          assert_equal({"schema" => "sftp://host/schema.json"}, properties)
          assert_equal({"schema" => schema}, RocketJob::Category::Input.display_properties("schema" => schema))
        end
      end

      describe "#format" do
        it "is one of the formats of IOStreams" do
          assert_predicate RocketJob::Category::Input.new(format: :psv), :valid?
          assert_predicate RocketJob::Category::Input.new(format: :auto), :valid?
          refute_predicate RocketJob::Category::Input.new(format: :unknown), :valid?
        end

        it "accepts a format that is registered after Rocket Job is loaded" do
          IOStreams::Tabular.register_format(:review_test, IOStreams::Tabular::Parser::Csv)

          assert_predicate RocketJob::Category::Input.new(format: :review_test), :valid?
          assert_includes RocketJob::Category::Base::FORMATS.to_a, :review_test
        ensure
          IOStreams::Tabular.deregister_format(:review_test)
        end

        it "lists the formats as the choices of the validation, as a form, such as Mission Control's, reads them" do
          choices = RocketJob::Category::Input.validators_on(:format).first.options[:in]

          assert_equal [nil, :auto], choices.first(2)
          assert_includes choices.map(&:to_s), "csv"
        end
      end

      describe "#format_options" do
        let(:layout) { {layout: [{size: 10, key: :name}, {size: 5, key: :zip, type: :integer}]} }

        it "reads records with the keys of the layout, as before v8" do
          category = RocketJob::Category::Input.new(format: :fixed, format_options: layout)

          assert_equal({name: "Jack", zip: 12_345}, category.parse_record("Jack      12345"))
          assert_nil category.schema
        end

        it "narrows the records to the input columns, as before v8" do
          category = RocketJob::Category::Input.new(format: :fixed, format_options: layout, columns: %w[name])

          assert_equal({"name" => "Jack"}, category.parse_record("Jack      12345"))
        end

        it "renders an Array result by the output columns, as before v8" do
          layout   = {layout: [{size: 10, key: "name"}, {size: 5, key: "zip"}]}
          category = RocketJob::Category::Output.new(format: :fixed, format_options: layout, columns: %w[zip name])

          assert_predicate category, :valid?
          assert_equal "Jack      12345", category.render(%w[12345 Jack])
        end

        it "can be set with skip_unknown, which does not change the records" do
          category = RocketJob::Category::Input.new(format: :fixed, format_options: layout, skip_unknown: true)

          assert_predicate category, :valid?
          assert_equal({name: "Jack", zip: 12_345}, category.parse_record("Jack      12345"))
        end

        it "cannot be set with a schema" do
          category = RocketJob::Category::Input.new(format: :fixed, format_options: layout,
                                                    schema: {"fields" => [{"name" => "name", "width" => 10}]})

          refute_predicate category, :valid?
          assert_equal ["Schema replaces format_options, which cannot be set with it"], category.errors.full_messages
        end

        it "does nothing when blank" do
          category = RocketJob::Category::Input.new(format: :fixed, format_options: {})

          assert_nil category.schema
          assert_predicate category, :valid?
        end

        it "raises when the layout is not valid" do
          assert_raises(IOStreams::Errors::InvalidLayout) do
            RocketJob::Category::Input.new(format_options: {layout: [{key: "name"}]})
          end
        end

        it "raises for an option other than the layout" do
          assert_raises(ArgumentError) do
            RocketJob::Category::Input.new(format_options: {layout: [{size: 10, key: :name}], skip_unknown: true})
          end
        end

        it "is a property of a category for a Dirmon entry or an UploadFileJob" do
          category = RocketJob::Category::Input.new(format: :fixed)

          assert_empty category.property_errors("format_options" => {"layout" => [{"size" => 10, "key" => "name"}]})
          assert_equal ["Format options is not valid"], category.property_errors("format_options" => {"layout" => [{}]})
        end
      end

      describe "saved before v8" do
        it "keeps its format_options, and reads its records with them" do
          category = RocketJob::Category::Input.instantiate(
            "_id"            => BSON::ObjectId.new,
            "format"         => "fixed",
            "format_options" => {"layout" => [{"size" => 10, "key" => "name"}, {"size" => 5, "key" => "zip"}]}
          )

          assert_nil category.schema
          assert_equal({"layout" => [{"size" => 10, "key" => "name"}, {"size" => 5, "key" => "zip"}]},
                       category.format_options)
          assert_equal({"name" => "Jack", "zip" => "12345"}, category.parse_record("Jack      12345"))
        end
      end

      describe "tabular" do
        it "returns tabular for the current settings" do
          schema = {
            "fields" => [{"name" => "action", "width" => 1}, {"name" => "date", "type" => "date", "width" => 10}],
            "width"  => "remainder"
          }
          category = RocketJob::Category::Input.new(format: :fixed, schema: schema)

          assert tabular = category.tabular
          assert_kind_of IOStreams::Tabular::Parser::Fixed, tabular.parser, tabular.parser.class.name
          # The schema reads each line into the values of its fields, by their types.
          assert_equal({"action" => "A", "date" => Date.new(2026, 10, 13)}, tabular.record_parse("A2026-10-13rest"))
        end

        it "names the columns with the deprecated columns, without a schema" do
          category = RocketJob::Category::Output.new(format: :csv, columns: %w[abc def])

          assert_equal %w[abc def], category.tabular.header.columns
          assert_equal "1,2", category.tabular.render({"def" => 2, "abc" => 1, "other" => 3})
        end

        it "writes the fields of the schema, in order" do
          schema   = {"fieldsMatch" => "subset", "fields" => [{"name" => "abc"}, {"name" => "def", "type" => "integer"}]}
          category = RocketJob::Category::Output.new(format: :csv, schema: schema)

          assert_equal "abc,def", category.render_header
          assert_equal "1,2", category.tabular.render({"def" => 2, "abc" => 1, "other" => 3})
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

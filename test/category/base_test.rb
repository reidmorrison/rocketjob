require_relative "../test_helper"

module Batch
  class CategoryTest < Minitest::Test
    class SchemaJob < RocketJob::Job
      include RocketJob::Batch

      input_category format: :csv

      def perform(record)
        record
      end
    end

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

      describe "#schema" do
        let(:schema) { {"fields" => [{"name" => "name"}, {"name" => "age", "type" => "integer"}]} }

        it "is valid as a Hash" do
          category = RocketJob::Category::Input.new(format: :csv, schema: schema)

          assert_predicate category, :valid?
        end

        it "is valid as the path or url of a JSON file, which is not read" do
          category = RocketJob::Category::Input.new(format: :csv, schema: "/no/such/schema.json")

          assert_predicate category, :valid?
        end

        it "is not valid when the Hash is not a schema" do
          category = RocketJob::Category::Input.new(format: :csv, schema: {"fields" => "name"})

          refute_predicate category, :valid?
          assert_match(/Schema is not valid/, category.errors.full_messages.first)
        end

        it "is not valid when it is not a Hash or a String" do
          category = RocketJob::Category::Input.new(format: :csv, schema: 12)

          refute_predicate category, :valid?
          assert_equal ["Schema must be a Hash, or the path or url of a JSON file"], category.errors.full_messages
        end

        it "needs a format" do
          category = RocketJob::Category::Input.new(schema: schema)

          refute_predicate category, :valid?
          assert_equal ["Schema needs a format, such as :csv, or :auto to take it from the file name"],
                       category.errors.full_messages
        end

        it "cannot be set with format_options" do
          category = RocketJob::Category::Output.new(
            format:         :fixed,
            schema:         schema,
            format_options: {"layout" => [{"size" => 5, "key" => "name"}]}
          )

          refute_predicate category, :valid?
          assert_equal ["Schema replaces format_options, which cannot be set with it"], category.errors.full_messages
        end

        it "builds the tabular from the schema, again once it is set" do
          category = RocketJob::Category::Output.new(format: :csv, columns: %w[a b])

          assert_equal "a,b", category.tabular.render_header

          category.columns = nil
          category.schema  = schema

          assert_equal "name,age", category.tabular.render_header
          assert_equal "Jack,21", category.tabular.render({"name" => "Jack", "age" => 21})
        end

        it "is kept when the job is saved and read back" do
          job = Batch::CategoryTest::SchemaJob.new
          job.input_category.schema = {fields: [{name: "name"}]}
          job.save!
          job = RocketJob::Job.find(job.id)

          assert_equal({"fields" => [{"name" => "name"}]}, job.input_category.schema)
          assert_predicate job, :valid?
        ensure
          job&.destroy
        end

        it "is shown without the credentials of its url" do
          properties = RocketJob::Category::Input.display_properties("schema" => "sftp://user:secret@host/schema.json")

          assert_equal({"schema" => "sftp://host/schema.json"}, properties)
          assert_equal({"schema" => schema}, RocketJob::Category::Input.display_properties("schema" => schema))
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

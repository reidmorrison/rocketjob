require_relative "../test_helper"

module Batch
  # How tabular input is read during upload, in each mode, and parsed by the workers, with the column restrictions
  # `allowed_columns`, `required_columns` and `skip_unknown`.
  class TabularInputTest < Minitest::Test
    class TabularJob < RocketJob::Job
      include RocketJob::Batch

      self.destroy_on_complete = false

      input_category format: :csv
      output_category

      def perform(record)
        record
      end
    end

    describe "Tabular input" do
      let(:job) { TabularJob.new }
      let(:csv) { "Name,Age,Extra\nJack,21,x\nJill,22,y\n" }
      let(:json) { %({"Name":"Jack","age":21,"extra":"x"}\n{"name":"Jill","age":22}\n) }

      after do
        job.cleanup!
      end

      def with_file(extension, data, &)
        IOStreams.temp_file("tabular_input_test", extension) do |path|
          ::File.write(path.to_s, data)
          yield(path.to_s)
        end
      end

      def upload(extension, data, **)
        with_file(extension, data) { |file_name| job.upload(file_name, **) }
      end

      def input_records
        job.input.collect(&:to_a).flatten(1)
      end

      def output_records
        job.save!
        job.perform_now
        job.output.collect(&:to_a).flatten(1)
      end

      describe "mode" do
        it "uploads lines by default" do
          assert_equal 2, upload(".csv", csv)

          assert_equal %w[name age extra], job.input_category.columns
          assert_equal ["Jack,21,x", "Jill,22,y"], input_records
        end

        it "uploads arrays in :array mode" do
          job.input_category.mode = :array

          assert_equal 2, upload(".csv", csv)

          assert_equal %w[name age extra], job.input_category.columns
          assert_equal [%w[Jack 21 x], %w[Jill 22 y]], input_records
          assert_equal [
            {"name" => "Jack", "age" => "21", "extra" => "x"},
            {"name" => "Jill", "age" => "22", "extra" => "y"}
          ], output_records
        end

        it "uploads hashes in :hash mode" do
          job.input_category.mode = :hash

          assert_equal 2, upload(".csv", csv)

          expected = [
            {"name" => "Jack", "age" => "21", "extra" => "x"},
            {"name" => "Jill", "age" => "22", "extra" => "y"}
          ]

          assert_equal expected, input_records
          assert_equal expected, output_records
        end

        it "uses stream_mode in place of the category's mode" do
          job.input_category.mode = :hash

          assert_equal 2, upload(".csv", csv, stream_mode: :array)

          assert_equal [%w[Jack 21 x], %w[Jill 22 y]], input_records
        end

        it "uploads arrays with supplied columns in :array mode" do
          job.input_category.mode    = :array
          job.input_category.columns = %w[name age extra]

          assert_equal 1, upload(".csv", "Jack,21,x\n")

          assert_equal [{"name" => "Jack", "age" => "21", "extra" => "x"}], output_records
        end

        it "reads the header row of arrays written to a block in :array mode" do
          job.input_category.mode = :array
          job.upload do |records|
            records << %w[Name Age]
            records << %w[Jack 21]
          end

          assert_equal %w[name age], job.input_category.columns
          assert_equal [{"name" => "Jack", "age" => "21"}], output_records
        end

        it "calls on_first with the header row in :array mode" do
          job.input_category.mode = :array
          header                  = nil
          upload(".csv", csv, on_first: ->(row) { header = row })

          assert_equal %w[Name Age Extra], header
        end
      end

      describe "column restrictions" do
        before do
          job.input_category.allowed_columns = %w[name age]
        end

        describe "csv" do
          it "rejects unknown columns" do
            assert_raises(IOStreams::Errors::InvalidHeader) { upload(".csv", csv) }
          end

          it "skips unknown columns" do
            job.input_category.skip_unknown = true
            upload(".csv", csv)

            assert_equal [{"name" => "Jack", "age" => "21"}, {"name" => "Jill", "age" => "22"}], output_records
          end

          it "applies them to a header row that is not cleansed" do
            job.input_category.header_cleanser = :none
            job.input_category.allowed_columns = %w[Name Age]
            job.input_category.skip_unknown    = true
            upload(".csv", csv)

            assert_equal %w[Name Age __rejected__Extra], job.input_category.columns
            assert_equal [{"Name" => "Jack", "Age" => "21"}, {"Name" => "Jill", "Age" => "22"}], output_records
          end

          it "applies them to supplied columns" do
            job.input_category.columns      = %w[name age extra]
            job.input_category.skip_unknown = true
            upload(".csv", "Jack,21,x\n")

            assert_equal [{"name" => "Jack", "age" => "21"}], output_records
          end

          it "rejects unknown supplied columns" do
            job.input_category.columns = %w[name age extra]

            assert_raises(IOStreams::Errors::InvalidHeader) { upload(".csv", "Jack,21,x\n") }
          end

          it "skips unknown columns in :hash mode" do
            job.input_category.mode         = :hash
            job.input_category.skip_unknown = true
            upload(".csv", csv)

            assert_equal [{"name" => "Jack", "age" => "21"}, {"name" => "Jill", "age" => "22"}], input_records
          end

          it "rejects unknown columns in :hash mode" do
            job.input_category.mode = :hash

            assert_raises(IOStreams::Errors::InvalidHeader) { upload(".csv", csv) }
          end
        end

        describe "json" do
          before do
            job.input_category.format = :json
          end

          it "skips unknown keys, and cleanses the others" do
            job.input_category.skip_unknown = true
            upload(".json", json)

            assert_equal [{"name" => "Jack", "age" => 21}, {"name" => "Jill", "age" => 22}], output_records
          end

          it "rejects unknown keys" do
            upload(".json", json)

            assert_raises(IOStreams::Errors::InvalidHeader) { output_records }
          end

          it "rejects a record without a required column" do
            job.input_category.allowed_columns  = nil
            job.input_category.required_columns = %w[extra]
            upload(".json", json)

            assert_raises(IOStreams::Errors::InvalidHeader) { output_records }
          end

          it "applies them when the format is detected from the file name" do
            job.input_category.format = :auto
            upload(".json", json)

            assert_equal :json, job.input_category.format
            assert_raises(IOStreams::Errors::InvalidHeader) { output_records }
          end

          it "are not applied when IOStreams.enforce_column_restrictions is false" do
            IOStreams.enforce_column_restrictions = false
            upload(".json", json)

            assert_equal [
              {"Name" => "Jack", "age" => 21, "extra" => "x"},
              {"name" => "Jill", "age" => 22}
            ], output_records
          ensure
            IOStreams.enforce_column_restrictions = true
          end
        end
      end
    end
  end
end

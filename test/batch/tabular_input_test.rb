require_relative "../test_helper"

module Batch
  # How tabular input is read during upload, and parsed by the workers.
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

      describe "blank lines before the header row" do
        let(:csv) { "\n  \nName,Age\nJack,21\n" }

        it "skips them, and reads the header row after them" do
          assert_equal 1, upload(".csv", csv)

          assert_equal %w[name age], job.input_category.columns
          assert_equal ["Jack,21"], input_records
          assert_equal [{"name" => "Jack", "age" => "21"}], output_records
        end

        it "skips them when they are written to a block" do
          count =
            job.upload do |records|
              records << ""
              records << "Name,Age"
              records << "Jack,21"
            end

          assert_equal 1, count
          assert_equal %w[name age], job.input_category.columns
          assert_equal [{"name" => "Jack", "age" => "21"}], output_records
        end

        it "calls on_first with the header row" do
          header = nil
          upload(".csv", csv, on_first: ->(row) { header = row })

          assert_equal "Name,Age", header
        end
      end

      describe "format :auto" do
        before do
          job.input_category.format = :auto
        end

        it "uploads the first record of a JSON file, which has no header row" do
          assert_equal 2, upload(".json", %({"name":"Jack"}\n{"name":"Jill"}\n))

          assert_equal :json, job.input_category.format
          assert_equal [{"name" => "Jack"}, {"name" => "Jill"}], output_records
        end

        it "reads the header row of a CSV file" do
          assert_equal 1, upload(".csv", "Name\nJack\n")

          assert_equal :csv, job.input_category.format
          assert_equal [{"name" => "Jack"}], output_records
        end
      end

      describe "on_first" do
        it "is called with the first record of a category without a format, which is not uploaded" do
          job.input_category.format = nil
          first                     = nil
          count                     = upload(".txt", "\nhello\nworld\n", on_first: ->(record) { first = record })

          assert_equal "", first
          assert_equal 2, count
          assert_equal %w[hello world], input_records
        end

        it "is called with the first record of a file without a header row, which is not uploaded" do
          job.input_category.columns = %w[name age]
          first                      = nil
          count                      = upload(".csv", "Jack,21\nJill,22\n", on_first: ->(record) { first = record })

          assert_equal "Jack,21", first
          assert_equal 1, count
          assert_equal ["Jill,22"], input_records
        end
      end
    end
  end
end

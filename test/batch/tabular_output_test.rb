require_relative "../test_helper"

module Batch
  # How the results of #perform are written in the format of an output category, see Category::Output#output_records,
  # and downloaded.
  class TabularOutputTest < Minitest::Test
    class CsvJob < RocketJob::Job
      include RocketJob::Batch

      self.destroy_on_complete = false

      output_category format: :csv,
                      schema: {"fields" => [{"name" => "name"}, {"name" => "age", "type" => "integer"}]}

      def perform(record)
        record
      end
    end

    describe "Tabular output" do
      let(:job) { CsvJob.new }

      after do
        job.cleanup!
      end

      def run_job(records)
        job.upload_slice(records)
        job.save!
        job.perform_now
      end

      def downloaded
        io = StringIO.new
        job.download(IOStreams.stream(io).file_name("people.csv"))
        io.string
      end

      it "writes the Hashes that #perform returns as the rows of the file, after its header row" do
        run_job([{"age" => 21, "name" => "Jack"}, {"name" => "J,ill", "age" => 22}])

        assert_equal "name,age\nJack,21\n\"J,ill\",22\n", downloaded
      end

      it "writes the Arrays that #perform returns by the position of the fields" do
        run_job([["Jack", 21]])

        assert_equal "name,age\nJack,21\n", downloaded
      end

      it "writes the header row of a file without rows" do
        job.output_category.nils = false
        job.define_singleton_method(:perform) { |_record| nil }
        run_job([{"name" => "Jack", "age" => 21}])

        assert_equal "name,age\n", downloaded
      end

      it "yields the header row and each row to a block" do
        run_job([{"name" => "Jack", "age" => 21}])
        lines = []
        job.download { |line| lines << line }

        assert_equal ["name,age", "Jack,21"], lines
      end

      it "raises for a String, which a format writes from values" do
        error = assert_raises(ArgumentError) { run_job(["Jack,21"]) }

        assert_includes error.message, "must return a Hash or an Array"
      end

      it "appends the rows of a retry to the rows that an earlier attempt wrote" do
        job.upload_slice([{"name" => "Jack", "age" => 21}, {"name" => "Jill", "age" => 22}])
        job.save!
        slice = job.input.first
        RocketJob::Sliced::Writer::Output.collect(job, input_slice: slice) { |writer| writer << {"name" => "Jack", "age" => 21} }
        RocketJob::Sliced::Writer::Output.collect(job, input_slice: slice, append: true) do |writer|
          writer << {"name" => "Jill", "age" => 22}
        end

        assert_equal ["Jack,21", "Jill,22"], job.output.first.to_a
        assert_equal %w[name age], job.output.first.records.header
      end
    end
  end
end

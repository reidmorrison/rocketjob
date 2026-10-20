require_relative "../test_helper"

module Batch
  # A file uploaded into an input category with a schema, which `upload` reads with IOStreams' `each(:slice)`: each slice
  # holds rows of the file as they are, with the header row of the file and its format, so that the workers read each
  # row by them.
  class FileSlicesTest < Minitest::Test
    class PeopleJob < RocketJob::Job
      include RocketJob::Batch

      self.destroy_on_complete = false

      input_category format: :csv,
                     schema: {
                       "fields" => [
                         {"name" => "name", "type" => "string"},
                         {"name" => "age", "type" => "integer"}
                       ]
                     }
      output_category

      def perform(record)
        record
      end
    end

    describe "a file uploaded with a schema" do
      let(:job) { PeopleJob.new }

      after do
        job.cleanup!
      end

      def upload(text)
        job.upload(StringIO.new(text), file_name: "people.csv")
      end

      def output_records
        job.output.collect(&:to_a).flatten(1)
      end

      def work
        job.save!
        job.start! if job.queued?
        job.rocket_job_work(RocketJob::Worker.new, false)
      end

      it "is stored in slices that hold its header row and format, by which the workers read its rows" do
        assert_equal 3, upload("Name,AGE\nJack,21\n\nJill,22\n")
        assert_equal 3, job.record_count

        stored = job.input.first.records

        assert_kind_of IOStreams::Slice, stored
        assert_equal %w[Name AGE], stored.header
        assert_equal :csv, stored.format
        assert_equal ["Jack,21", "", "Jill,22"], stored.to_a

        work

        assert_predicate job, :completed?
        assert_equal [{"name" => "Jack", "age" => 21}, {"name" => "Jill", "age" => 22}], output_records
      end

      it "fails the record whose perform raises, which a retry processes again" do
        upload("Name,AGE\nJack,21\nJill,22\nBob,23\n")
        failures = 0
        job.stub(:perform, lambda { |record|
          if record["name"] == "Jill" && failures.zero?
            failures += 1
            raise(ArgumentError, "Jill")
          end
          record
        }) do
          work

          assert_equal 2, job.input.first.processing_record_number
          job.retry!
          work
        end
        names = output_records.collect { |record| record["name"] }

        assert_predicate job, :completed?
        assert_equal %w[Jack Jill Bob], names
      end

      %i[none compress encrypt].each do |serializer|
        it "is stored with the #{serializer} serializer" do
          job.input_category.serializer = serializer
          upload("Name,AGE\nJack,21\n")

          assert_equal %w[Name AGE], job.input.first.records.header
          work

          assert_equal [{"name" => "Jack", "age" => 21}], output_records
        end
      end
    end
  end
end

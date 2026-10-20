require_relative "../test_helper"

module Batch
  # Slices of the rows of a file, which IOStreams reads in slices, see `IOStreams::Stream#each(:slice)`, and which carry
  # the header row of their file and its format, so that the workers read each row by them.
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

    describe "slices of the rows of a file" do
      let(:job) { PeopleJob.new }

      after do
        job.cleanup!
      end

      def rows(*lines, header: %w[Name AGE])
        IOStreams::Slice.new(lines, header: header, format: :csv)
      end

      def output_records
        job.output.collect(&:to_a).flatten(1)
      end

      def work
        job.save!
        job.start! if job.queued?
        job.rocket_job_work(RocketJob::Worker.new, false)
      end

      it "are uploaded, and read by the header row that they carry" do
        assert_equal 3, job.upload_slice(rows("Jack,21", "", "Jill,22"))
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

      it "are read by the header row of their own file" do
        job.upload_slice(rows("Jack,21"))
        job.upload_slice(rows("22,Jill", header: %w[age name]))
        job.input_category.schema = job.input_category.schema.merge("fieldsMatch" => "equal")
        work

        assert_equal [{"name" => "Jack", "age" => 21}, {"name" => "Jill", "age" => 22}], output_records
      end

      it "fail the record that cannot be read, which is processed again once it is corrected" do
        job.upload_slice(rows("Jack,21", "Jill,x", "Bob,23"))
        work
        slice = job.input.first

        assert_predicate job, :failed?
        assert_equal "IOStreams::Errors::InvalidValue", slice.exception.class_name
        assert_equal 2, slice.processing_record_number
        assert_equal "Jill,x", slice.failed_record

        # As Mission Control corrects a record: the slice keeps the header row of its file.
        slice.replace_record(1, "Jill,22")
        slice.save!
        job.retry!
        work

        names = output_records.collect { |record| record["name"] }

        assert_predicate job, :completed?
        assert_equal %w[Jack Jill Bob], names
      end

      it "fail the record whose perform raises, which is processed again" do
        job.upload_slice(rows("Jack,21", "Jill,22", "Bob,23"))
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
        it "are stored with the #{serializer} serializer" do
          job.input_category.serializer = serializer
          job.upload_slice(rows("Jack,21"))

          assert_equal %w[Name AGE], job.input.first.records.header
          work

          assert_equal [{"name" => "Jack", "age" => 21}], output_records
        end
      end
    end
  end
end

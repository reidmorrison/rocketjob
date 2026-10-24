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

    class AfterSliceJob < PeopleJob
      after_slice :fail_after_slice

      def fail_after_slice
        raise(ArgumentError, "after_slice")
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
        assert_equal ["Jack,21", "", "Jill,22"], stored.rows

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

      it "keeps the slices of an earlier file when a later one fails" do
        job.input_category.validate_rows = true
        job.input_category.slice_size    = 1
        upload("Name,AGE\nJack,21\n")

        # The slice of Jill is stored before Bob's value raises.
        assert_raises(IOStreams::Errors::InvalidValue) { upload("Name,AGE\nJill,22\nBob,x\n") }
        assert_equal 1, job.input.count
        assert_equal 1, job.record_count

        work

        assert_predicate job, :completed?
        assert_equal [{"name" => "Jack", "age" => 21}], output_records
      end

      it "raises for a path with another schema, since the workers read each slice with the category's" do
        path  = IOStreams.stream(StringIO.new("name\nJack\n")).file_name("people.csv")
        error = assert_raises(ArgumentError) { job.upload(path.schema("fields" => [{"name" => "name"}])) }

        assert_includes error.message, "on the category"
        assert_equal 0, job.input.count
      end

      it "accepts a path with the category's schema" do
        path = IOStreams.stream(StringIO.new("Name,AGE\nJack,21\n")).file_name("people.csv")

        assert_equal 1, job.upload(path.schema(job.input_category.schema))
      end

      it "resumes a slice without reading the records that an earlier attempt processed" do
        upload("Name,AGE\nJack,x\nJill,22\n")
        slice = job.input.first
        slice.processing_record_number = 2
        slice.save!

        work

        assert_predicate job, :completed?
        assert_equal [{"name" => "Jill", "age" => 22}], output_records
      end

      it "fails a slice whose rows cannot be read, rather than the worker" do
        job.input_category.serializer = :none
        upload("Name,AGE\nJack,21\n")
        id       = job.input.first.id
        stored   = job.input.collection.find(_id: id).first["records"]
        document = Hash.from_bson(BSON::ByteBuffer.new(stored.data))
        document["s"]["format"] = "no_such_format"
        job.input.collection.update_one({_id: id}, {"$set" => {"records" => BSON::Binary.new(document.to_bson.to_s)}})

        work
        slice = job.input.first

        assert_predicate job, :failed?
        assert_predicate slice, :failed?
        assert_equal "ArgumentError", slice.exception.class_name
        assert_includes slice.exception.message, "no_such_format"
      end

      describe "when an after_slice callback fails" do
        let(:job) { AfterSliceJob.new }

        it "names the last record of the slice" do
          upload("Name,AGE\nJack,21\nJill,22\n")
          work
          slice  = job.input.first
          failed = []
          job.input.each_failed_record { |record, _slice| failed << record }

          assert_predicate slice, :failed?
          assert_equal 2, slice.processing_record_number
          assert_equal 2, slice.current_record_number
          assert_equal ["Jill,22"], failed
        end
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

      describe "record and line numbers" do
        # Returns, for each record that perform receives, its name, record number and line number, and the log tags.
        def numbers_of_records
          job.stub(:perform, lambda { |record|
            [record&.fetch("name"), job.rocket_job_record_number, job.rocket_job_line_number, SemanticLogger.named_tags.slice(:record, :line)]
          }) do
            work
          end
          output_records
        end

        it "are those of each row in its file, across slices, after a blank row and a value with line breaks" do
          job.input_category.slice_size = 2
          upload("Name,AGE\nJack,21\n\n\"Jill\nSmith\",22\nJoe,23\n")

          expected = [
            ["Jack", 1, 2, {"record" => 1, "line" => 2}],
            [nil, 2, 3, {"record" => 2, "line" => 3}],
            ["Jill\nSmith", 3, 4, {"record" => 3, "line" => 4}],
            ["Joe", 4, 6, {"record" => 4, "line" => 6}]
          ]

          assert_equal expected, numbers_of_records
        end

        it "of the rows after a record removed from a failed slice stay those in its file" do
          upload("Name,AGE\nJack,21\nBad,1\nJill,22\n")
          job.stub(:perform, ->(record) { raise(ArgumentError, "Bad") if record["name"] == "Bad" }) do
            work
          end
          slice = job.input.failed.first

          assert_equal 2, slice.current_record_number
          assert_equal 3, slice.current_line_number
          slice.delete_record(slice.processing_record_number - 1)
          slice.save!
          job.retry!

          assert_equal [["Jill", 3, 4, {"record" => 3, "line" => 4}]], numbers_of_records
        end
      end
    end
  end
end

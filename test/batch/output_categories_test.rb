require_relative "../test_helper"

module Batch
  class OutputCategoriesTest < Minitest::Test
    class MainCategoryJob < RocketJob::Job
      include RocketJob::Batch

      output_category

      def perform(record)
        record
      end
    end

    class SingleCategoryJob < RocketJob::Job
      include RocketJob::Batch

      output_category(name: :other)

      def perform(record)
        RocketJob::Batch::Result.new(:other, record)
      end
    end

    class BadCategoryJob < RocketJob::Job
      include RocketJob::Batch

      output_category(name: :other)

      def perform(record)
        RocketJob::Batch::Result.new(:blah, record)
      end
    end

    class TwoCategoryJob < RocketJob::Job
      include RocketJob::Batch

      output_category(name: :first)
      output_category(name: :second)

      def perform(record)
        results = RocketJob::Batch::Results.new
        results << RocketJob::Batch::Result.new(:first, record)
        results << RocketJob::Batch::Result.new(:second, record)
        results
      end
    end

    class ComplexCategoryJob < RocketJob::Job
      include RocketJob::Batch

      output_category(name: :first, serializer: :compress)
      output_category(name: :second, serializer: :encrypt)

      def perform(record)
        results = RocketJob::Batch::Results.new
        results << RocketJob::Batch::Result.new(:first, record)
        results << RocketJob::Batch::Result.new(:second, record)
        results
      end
    end

    class BZip2CategoryJob < RocketJob::Job
      include RocketJob::Batch

      output_category(serializer: :bz2)

      def perform(record)
        record
      end
    end

    describe RocketJob::Batch::Categories do
      after do
        @job.destroy if @job && !@job.new_record?
      end

      let(:lines) { 5.times.collect { |i| "line#{i + 1}" } }

      describe "default main category job" do
        it "writes to the main category" do
          @job = MainCategoryJob.new
          @job.upload_slice(lines)
          @job.perform_now
          assert @job.completed?, -> { @job.attributes.ai }
          assert_equal lines, @job.output(:main).first.to_a
        end
      end

      describe "single other category job" do
        it "writes to the other category" do
          @job = SingleCategoryJob.new
          @job.upload_slice(lines)
          @job.perform_now
          assert @job.completed?, -> { @job.attributes.ai }
          assert_equal lines, @job.output(:other).first.to_a
        end
      end

      describe "bad category from perform" do
        it "raises an exception" do
          @job = BadCategoryJob.new
          @job.upload_slice(lines)
          assert_raises ArgumentError do
            @job.perform_now
          end
        end
      end

      describe "two category job" do
        it "writes to both categories" do
          @job = TwoCategoryJob.new
          @job.upload_slice(lines)
          @job.perform_now
          assert @job.completed?, -> { @job.attributes.ai }
          assert_equal lines, @job.output(:first).first.to_a
          assert_equal lines, @job.output(:second).first.to_a
        end
      end

      describe "complex category job" do
        it "writes compressed to one category and encrypted to another" do
          @job = ComplexCategoryJob.new
          @job.upload_slice(lines)
          @job.perform_now
          assert @job.completed?, -> { @job.attributes.ai }
          assert_equal lines, @job.output(:first).first.to_a
          assert_equal lines, @job.output(:second).first.to_a
        end
      end

      # Performs BZip2 compression on each worker and then just writes the binary data to a BZip2 file
      # Fastest compression available in Rocket Job for very large files.
      describe "BZip2 output job" do
        it "writes compressed in BZip2 format" do
          @job = BZip2CategoryJob.new
          @job.upload_slice(lines)
          @job.perform_now
          assert @job.completed?, -> { @job.attributes.ai }

          # Verify that the output slice is compressed using BZip2
          str = lines.join("\n") + "\n"
          s   = StringIO.new
          IOStreams::Bzip2::Writer.stream(s) { |io| io.write(str) }

          assert_equal s.string, @job.output(:main).first.to_a.first
        end
      end

      describe "#as_document" do
        it "serializes default" do
          job = MainCategoryJob.new
          assert h = job.as_document
          assert_equal MainCategoryJob.name, h["_type"]
          assert_equal 1, h["output_categories"].size
          assert_equal "main", h["output_categories"].first["name"]
        end

        it "serializes named output" do
          job = SingleCategoryJob.new
          assert h = job.as_document
          assert_equal SingleCategoryJob.name, h["_type"]
          assert_equal 1, h["output_categories"].size
          assert_equal "other", h["output_categories"].first["name"]
        end

        it "serializes multiple outputs" do
          job = TwoCategoryJob.new
          assert h = job.as_document
          assert_equal TwoCategoryJob.name, h["_type"]
          assert_equal 2, h["output_categories"].size
          assert_equal "first", h["output_categories"].first["name"]
          assert_equal "second", h["output_categories"].last["name"]
        end
      end

      describe "#reload" do
        it "restores" do
          job = TwoCategoryJob.create
          job.reload
          assert job.is_a?(TwoCategoryJob)
          assert_equal 2, job.output_categories.size
          assert_equal :first, job.output_categories.first.name
          assert_equal :second, job.output_categories.last.name
        end
      end
    end
  end
end

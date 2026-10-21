require_relative "../test_helper"

module Jobs
  class ConversionJobTest < Minitest::Test
    describe RocketJob::Jobs::ConversionJob do
      before do
        RocketJob::Jobs::ConversionJob.delete_all
      end

      it "converts a file in the encoding of its input category" do
        IOStreams.temp_file("conversion_job_test", ".csv") do |source|
          IOStreams.temp_file("conversion_job_test", ".psv") do |target|
            ::File.binwrite(source.to_s, "name,city\nJos\xE9,Z\xFCrich\n".b)
            job                           = RocketJob::Jobs::ConversionJob.new
            job.input_category.file_name  = source.to_s
            job.input_category.encoding   = "Windows-1252"
            job.output_category.file_name = target.to_s
            job.output_category.schema    = {"fields" => [{"name" => "name"}, {"name" => "city"}]}
            job.save!
            job.perform_now

            assert_predicate job, :completed?
            assert_equal "name|city\nJosé|Zürich\n", ::File.read(target.to_s)
          end
        end
      end

      it "converts JSON to PSV by the schema of its output category" do
        IOStreams.temp_file("conversion_job_test", ".json") do |source|
          IOStreams.temp_file("conversion_job_test", ".psv") do |target|
            ::File.write(source.to_s, %({"city":"Paris","name":"Jack"}\n{"name":"Jill","city":"Rome"}\n))
            job                           = RocketJob::Jobs::ConversionJob.new
            job.input_category.file_name  = source.to_s
            job.output_category.file_name = target.to_s
            job.output_category.schema    = {"fields" => [{"name" => "name"}, {"name" => "city"}]}
            job.save!
            job.perform_now

            assert_predicate job, :completed?
            assert_equal "name|city\nJack|Paris\nJill|Rome\n", ::File.read(target.to_s)
          end
        end
      end
    end
  end
end

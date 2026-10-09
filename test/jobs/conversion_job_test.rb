require_relative "../test_helper"

module Jobs
  class ConversionJobTest < Minitest::Test
    describe RocketJob::Jobs::ConversionJob do
      before do
        RocketJob::Jobs::ConversionJob.delete_all
      end

      it "converts a file in the encoding of its input category" do
        IOStreams.temp_file("conversion_job_test", ".csv") do |source|
          IOStreams.temp_file("conversion_job_test", ".json") do |target|
            ::File.binwrite(source.to_s, "name,city\nJos\xE9,Z\xFCrich\n".b)
            job                           = RocketJob::Jobs::ConversionJob.new
            job.input_category.file_name  = source.to_s
            job.input_category.encoding   = "Windows-1252"
            job.output_category.file_name = target.to_s
            job.save!
            job.perform_now

            assert_predicate job, :completed?
            assert_equal({"name" => "José", "city" => "Zürich"}, JSON.parse(::File.read(target.to_s)))
          end
        end
      end
    end
  end
end

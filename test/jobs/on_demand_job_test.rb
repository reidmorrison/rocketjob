require_relative "../test_helper"

module Jobs
  class OnDemandJobTest < Minitest::Test
    describe RocketJob::Jobs::OnDemandJob do
      before do
        RocketJob::Jobs::OnDemandJob.delete_all
      end

      describe "#perform" do
        it "hello world" do
          code = <<~CODE
            logger.info 'Hello World'
          CODE

          job = RocketJob::Jobs::OnDemandJob.new(code: code)
          job.perform_now
        end

        it "retain output" do
          code = <<~CODE
            data["result"] = "h" * 24
          CODE

          job = RocketJob::Jobs::OnDemandJob.new(code: code)
          job.perform_now
          assert_equal "h" * 24, job.data["result"]
        end

        it "accepts input data" do
          code = <<~CODE
            data["result"] = data["a"] * data["b"]
          CODE

          job = RocketJob::Jobs::OnDemandJob.new(
            code: code,
            data: {"a" => 10, "b" => 2}
          )
          job.perform_now
          assert_equal 20, job.data["result"]
        end

        it "validates code" do
          code = <<~CODE
            def bad code
          CODE

          job = RocketJob::Jobs::OnDemandJob.new(code: code)
          refute job.valid?
          assert_raises ::Mongoid::Errors::Validations do
            job.perform_now
          end
        end
      end
    end
  end
end

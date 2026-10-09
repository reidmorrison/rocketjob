require_relative "test_helper"

class JobExceptionTest < Minitest::Test
  describe RocketJob::JobException do
    describe ".from_exception" do
      it "keeps the class name, message and backtrace" do
        exception = RuntimeError.new("Job failed")
        exception.set_backtrace(["job.rb:1"])
        job_exception = RocketJob::JobException.from_exception(exception, worker_name: "server:1")

        assert_equal "RuntimeError", job_exception.class_name
        assert_equal "Job failed", job_exception.message
        assert_equal ["job.rb:1"], job_exception.backtrace
        assert_equal "server:1", job_exception.worker_name
      end

      it "shows each byte of the message that is not valid UTF-8 as \\xHH, so that it can be saved" do
        job_exception = RocketJob::JobException.from_exception(ArgumentError.new("Unknown customer: Jos\xE9"))

        assert_equal "Unknown customer: Jos\\xE9", job_exception.message
      end

      it "keeps the characters of a binary message that is valid UTF-8" do
        job_exception = RocketJob::JobException.from_exception(ArgumentError.new("José not found".b))

        assert_equal "José not found", job_exception.message
      end
    end

    describe "#message=" do
      it "stores a message supplied as text as valid UTF-8" do
        job_exception = RocketJob::JobException.new(message: "caf\xE9.csv failed")

        assert_equal "caf\\xE9.csv failed", job_exception.message
      end

      it "keeps nil" do
        assert_nil RocketJob::JobException.new(message: nil).message
      end
    end

    describe "#backtrace=" do
      it "stores each line as valid UTF-8" do
        job_exception = RocketJob::JobException.new(backtrace: ["/data/caf\xE9.rb:1", "job.rb:2"])

        assert_equal ["/data/caf\\xE9.rb:1", "job.rb:2"], job_exception.backtrace
      end
    end
  end
end

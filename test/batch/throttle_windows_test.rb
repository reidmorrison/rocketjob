require_relative "../test_helper"

module Batch
  class ThrottleWindowsTest < Minitest::Test
    class AfterHoursJob < RocketJob::Job
      include RocketJob::Batch
      include RocketJob::Batch::ThrottleWindows

      # Monday through Thursday the job can start processing at 5pm Eastern.
      self.primary_schedule = "0 17 * * 1-4 America/New_York"
      # Slices are allowed to run until 8am the following day, which is 15 hours long:
      self.primary_duration = 15.hours

      # The slices for this job can run all weekend long, starting Friday at 5pm Eastern.
      self.secondary_schedule = "0 17 * * 5 America/New_York"
      # Slices are allowed to run until 5am on Monday morning, which is 60 hours long:
      self.secondary_duration = 63.hours

      input_category slice_size: 1

      def perform(record)
        record
      end
    end

    describe RocketJob::Batch::ThrottleWindows do
      before do
        RocketJob::Job.destroy_all
      end

      after do
        RocketJob::Job.destroy_all
      end

      let(:job) do
        job = AfterHoursJob.new
        job.upload do |stream|
          stream << "first"
          stream << "second"
        end
        job.save!
        assert_equal 2, job.input.count
        job
      end

      let(:worker) { RocketJob::Worker.new }

      describe "#throttle_outside_window?" do
        it "outside window" do
          time = Time.parse("2020-06-13 17:30:18 +0000") # Saturday
          Time.stub(:now, time) do
            schedule = "0 17 * * 1-5 UTC"
            duration = 1.hour
            assert job.send(:throttle_outside_window?, schedule, duration)
          end
        end

        it "inside window" do
          time = Time.parse("2020-06-13 17:30:18 +0000") # Saturday
          Time.stub(:now, time) do
            schedule = "0 17 * * * UTC"
            duration = 1.hour
            refute job.send(:throttle_outside_window?, schedule, duration)
          end
        end

        it "start of window" do
          time = Time.parse("2020-06-13 17:00:00 +0000") # Saturday
          Time.stub(:now, time) do
            schedule = "0 17 * * * UTC"
            duration = 1.hour
            refute job.send(:throttle_outside_window?, schedule, duration)
          end
        end

        it "end of window" do
          time = Time.parse("2020-06-13 17:59:59 +0000") # Saturday
          Time.stub(:now, time) do
            schedule = "0 17 * * * UTC"
            duration = 1.hour
            refute job.send(:throttle_outside_window?, schedule, duration)
          end
        end

        it "passed end of window" do
          time = Time.parse("2020-06-13 18:00:00 +0000") # Saturday
          Time.stub(:now, time) do
            schedule = "0 17 * * * UTC"
            duration = 1.hour
            assert job.send(:throttle_outside_window?, schedule, duration)
          end
        end
      end

      describe "#throttle_windows_exceeded?" do
        it "runs during primary window" do
          time = Time.parse("2020-06-10 17:10:00 -0400") # Wednesday
          Time.stub(:now, time) do
            refute job.send(:throttle_windows_exceeded?)
          end
        end

        it "stops outside primary window" do
          time = Time.parse("2020-06-10 16:30:00 -0400") # Wednesday
          Time.stub(:now, time) do
            assert job.send(:throttle_windows_exceeded?)
          end
        end

        it "stops outside primary window with now secondary schedule" do
          job.secondary_schedule = nil
          time                   = Time.parse("2020-06-10 16:30:00 -0400") # Wednesday
          Time.stub(:now, time) do
            assert job.send(:throttle_windows_exceeded?)
          end
        end

        it "runs during secondary window" do
          time = Time.parse("2020-06-13 1:00:00 -0400") # Saturday
          Time.stub(:now, time) do
            refute job.send(:throttle_windows_exceeded?)
          end
        end

        it "stops outside secondary window" do
          time = Time.parse("2020-06-08 10:00:00 -0400") # Monday
          Time.stub(:now, time) do
            assert job.send(:throttle_windows_exceeded?)
          end
        end

        it "stops outside secondary window when primary schedule is nil" do
          time = Time.parse("2020-06-08 10:00:00 -0400") # Monday
          Time.stub(:now, time) do
            assert job.send(:throttle_windows_exceeded?)
          end
        end
      end

      describe "#rocket_job_work" do
        before do
          job.start!
        end

        it "process all slices inside window" do
          time = Time.parse("2020-06-10 17:10:00 -0400") # Wednesday
          Time.stub(:now, time) do
            refute job.rocket_job_work(worker, true)
          end
          assert job.completed?, -> { job.ai }
          assert_equal 0, job.input.count
        end

        it "stop processing outside window" do
          time = Time.parse("2020-06-10 16:30:00 -0400") # Wednesday
          Time.stub(:now, time) do
            assert job.rocket_job_work(worker, true)
          end
          assert job.running?, -> { job.ai }
          assert_equal 2, job.input.count
        end
      end
    end
  end
end

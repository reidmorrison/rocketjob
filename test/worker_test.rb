require_relative 'test_helper'

class WorkerTest < Minitest::Test
  class SimpleJob < RocketJob::Job
    def perform
      # Do something here
    end
  end

  class ThrottledJob < RocketJob::Job
    self.throttle_running_jobs = 1

    def perform
      # Do something here
    end
  end

  class BeforeStartExceptionJob < RocketJob::Job
    before_start :throw_exception

    def perform
    end

    def throw_exception
      raise(ArgumentError, "Oh No")
    end
  end

  class AfterStartExceptionJob < RocketJob::Job
    after_start :throw_exception

    def perform
    end

    def throw_exception
      raise(ArgumentError, "Oh No")
    end
  end

  class BeforePerformExceptionJob < RocketJob::Job
    before_perform :throw_exception

    def perform
    end

    def throw_exception
      raise(ArgumentError, "Oh No")
    end
  end

  class SimpleBatchJob < RocketJob::Job
    include RocketJob::Batch

    self.destroy_on_complete = false
    self.collect_output      = true
    self.slice_size          = 10

    def perform(record)
      record
    end
  end

  describe RocketJob::Worker do
    let(:job) { SimpleJob.new }
    let(:throttled_job) { ThrottledJob.new }
    let(:batch_job) { SimpleBatchJob.new }
    let(:worker) { RocketJob::Worker.new(inline: true) }

    before do
      RocketJob::Job.delete_all
    end

    after do
      RocketJob::Job.delete_all
    end

    describe '#random_wait_interval' do
      it 'returns random value between 0 and max_poll_seconds' do
        assert seconds = worker.random_wait_interval
        assert seconds >= 0, seconds
        assert seconds <= RocketJob::Config.max_poll_seconds, seconds
      end
    end

    describe '#add_to_current_filter' do
      it 'creates new filter' do
        assert_equal({}, worker.current_filter)
        worker.add_to_current_filter(:id.nin => ['1234'])
        assert_equal({:id.nin => ['1234']}, worker.current_filter)
      end

      it 'adds to an existing filter' do
        assert_equal({}, worker.current_filter)
        worker.add_to_current_filter(:id.nin => ['1234'])
        worker.add_to_current_filter(_type: /MyJob/)
        assert_equal({:id.nin => ["1234"], _type: /MyJob/}, worker.current_filter)
      end

      it 'adds to an existing filter key' do
        assert_equal({}, worker.current_filter)
        worker.add_to_current_filter(:id.nin => ['1234'])
        worker.add_to_current_filter(:id.nin => ['5678'])
        assert_equal({:id.nin => ["1234", "5678"]}, worker.current_filter)
      end

      it 'overrides existing key when not an array' do
        assert_equal({}, worker.current_filter)
        worker.add_to_current_filter(id: '1234')
        worker.add_to_current_filter(id: '5678')
        assert_equal({id: "5678"}, worker.current_filter)
      end
    end

    describe '#find_and_assign_job' do
      it 'returns nil if no jobs available' do
        assert_nil worker.find_and_assign_job
      end

      it 'returns the first job' do
        job.save!
        assert found_job = worker.find_and_assign_job, 'Failed to find job'
        assert_equal job.id, found_job.id
      end

      it 'assigns worker name and updates state to running' do
        job.save!
        assert found_job = worker.find_and_assign_job, 'Failed to find job'
        found_job.reload
        assert_equal worker.name, found_job.worker_name
        assert found_job.running?
      end

      it 'ignores future dated jobs' do
        job.run_at = Time.now + 1.hour
        job.save!
        assert_nil worker.find_and_assign_job
      end

      it 'Process future dated jobs when time is now' do
        job.run_at = Time.now
        job.save!
        assert found_job = worker.find_and_assign_job, 'Failed to find job'
        assert_equal job.id, found_job.id
      end

      it 'Process future dated jobs when time is in the past' do
        job.run_at = Time.now - 1.hour
        job.save!
        assert found_job = worker.find_and_assign_job, 'Failed to find job'
        assert_equal job.id, found_job.id
      end

      it 'fetches processing batch jobs' do
        batch_job.start!
        assert_equal :before, batch_job.sub_state
        assert_nil worker.find_and_assign_job

        batch_job.sub_state = :processing
        batch_job.save!
        assert found_job = worker.find_and_assign_job, 'Failed to find job'
        assert_equal batch_job.id, found_job.id

        batch_job.sub_state = :after
        batch_job.save!
        assert_nil worker.find_and_assign_job
      end

      it 'excludes filtered jobs' do
        job.save!
        worker.add_to_current_filter(:id.nin => [job.id])
        assert_nil worker.find_and_assign_job
      end

      it 'sorts based on priority' do
        batch_job.priority = 50
        batch_job.save!
        job.priority = 30
        job.save!
        assert found_job = worker.find_and_assign_job, 'Failed to find job'
        assert_equal job.id, found_job.id

        job.priority = 90
        job.save!
        assert found_job = worker.find_and_assign_job, 'Failed to find job'
        assert_equal batch_job.id, found_job.id
      end

      it 'excludes running regular jobs' do
        job.start!
        assert_nil worker.find_and_assign_job
      end
    end

    describe '#next_available_job' do
      #   it 'Skip expired jobs' do
      #     count           = RocketJob::Job.count
      #     @job.expires_at = Time.now - 100
      #     @job.save!
      #     assert_nil RocketJob::Job.rocket_job_next_job(@worker_name)
      #     assert_equal count, RocketJob::Job.count
      #   end
      #
      it 'returns nil when no jobs available' do
        assert_nil worker.next_available_job
      end

      it 'returns a queued job' do
        job.save!
        assert found_job = worker.next_available_job
        assert_equal job.id, found_job.id
      end

      it 'returns a running batch job' do
        batch_job.start
        batch_job.sub_state = :processing
        batch_job.save!
        assert found_job = worker.next_available_job
        assert_equal batch_job.id, found_job.id
      end

      it 'destroys expired jobs' do
        job.expires_at = 1.day.ago
        job.save!
        assert_nil worker.next_available_job
        assert_nil RocketJob::Job.where(id: job.id).first
      end

      it 'returns the first non-expired job' do
        job.expires_at = 1.day.ago
        job.save!

        batch_job.start
        batch_job.sub_state = :processing
        batch_job.save!
        assert found_job = worker.next_available_job
        assert_equal batch_job.id, found_job.id
      end

      it 'handles exceptions when a job starts' do
        job = BeforeStartExceptionJob.create!
        assert_nil worker.next_available_job
        assert job.reload.failed?
      end

      it 'handles exceptions when a job starts' do
        job = AfterStartExceptionJob.create!
        assert_nil worker.next_available_job
        assert job.reload.failed?
      end

      describe 'throttles' do
        it 'honors job throttles' do
          RocketJob::Job.destroy_all
          throttled_job.start!
          ThrottledJob.create!
          assert_nil worker.next_available_job
        end

        it 'return the job when others are queued, paused, failed, or complete' do
          job = ThrottledJob.create!
          ThrottledJob.create!(state: :failed)
          ThrottledJob.create!(state: :complete)
          ThrottledJob.create!(state: :paused)
          assert found_job = worker.next_available_job
          assert_equal job.id, found_job.id
        end

        it 'return nil when other jobs are running' do
          ThrottledJob.create!
          job = ThrottledJob.new
          job.start!
          assert_nil worker.next_available_job
        end

        it 'add job to filter when other jobs are running' do
          ThrottledJob.create!
          job = ThrottledJob.new
          job.start!
          assert_nil worker.next_available_job
          assert_equal({:_type.nin => [ThrottledJob.name]}, worker.current_filter)
        end
      end
    end

    describe "#reset_filter_if_expired" do
      it "does not reset when time has not passed" do
        worker.add_to_current_filter(:id.nin => ['1234'])
        worker.reset_filter_if_expired
        assert_equal({:id.nin => ['1234']}, worker.current_filter)
      end

      it "resets filter when time has passed" do
        worker.add_to_current_filter(:id.nin => ['1234'])
        Time.stub(:now, 1.hour.from_now) do
          worker.reset_filter_if_expired
        end
        assert_equal({}, worker.current_filter)
      end

      it "resets filter to default where filter" do
        RocketJob::Config.stub(:where_filter, {:id.nin => ['5678']}) do
          worker.add_to_current_filter(:id.nin => ['1234'])
          Time.stub(:now, 1.hour.from_now) do
            worker.reset_filter_if_expired
          end
          assert_equal({:id.nin => ['5678']}, worker.current_filter)
        end
      end
    end
  end
end

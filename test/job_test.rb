require File.join(File.dirname(__FILE__), 'test_helper')

# Unit Test for BatchJob::Job
class JobTest < Minitest::Test
  context BatchJob::Job do
    setup do
      @description = 'Hello World'
      @job = BatchJob::Job.new(
        description: @description
      )
    end

    teardown do
      @job.destroy unless @job.new_record?
    end

    context '.config' do
      should 'support multiple databases' do
        assert_equal 'test_batch_job', BatchJob::Job.collection.db.name
      end
    end

    context '#save!' do
      should 'save a blank job' do
        @job.save!
        assert_nil   @job.assigned_to
        assert_nil   @job.completed_at
        assert       @job.created_at
        assert_equal @description, @job.description
        assert_equal false, @job.destroy_on_completion
        assert_equal 0, @job.email_addresses.count
        assert_nil   @job.expires_at
        assert_nil   @job.group
        assert_equal({}, @job.parameters)
        assert_equal 0, @job.percent_complete
        assert_equal 50, @job.priority
        assert_equal true, @job.repeatable
        assert_equal 0, @job.retry_count
        assert_nil   @job.run_at
        assert_nil   @job.schedule
        assert_nil   @job.started_at
        assert_equal :queued, @job.state
      end
    end

    context '#status' do
      should 'return status for a queued job' do
        assert_equal true, @job.queued?
        h = @job.status
        assert_equal :queued,      h[:state]
        assert_equal @description, h[:description]
        assert h[:wait_seconds]
        assert h[:status] =~ /Queued for \d+.\d\d seconds/
      end
    end

  end
end

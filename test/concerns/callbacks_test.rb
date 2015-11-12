require_relative '../test_helper'
require_relative '../jobs/test_job'

# Unit Test for RocketJob::Job
class JobTest < Minitest::Test
  describe RocketJob::Concerns::Callbacks do
    before do
      @description = 'Hello World'
      @arguments   = [{key: 'value'}]
      @event_job   = Jobs::EventJob.new(
        description:         @description,
        arguments:           @arguments,
        destroy_on_complete: false,
        collect_output:      true
      )
    end

    after do
      @event_job.destroy if @event_job && !@event_job.new_record?
    end

    describe '#callbacks' do
      it 'calls callbacks' do
        named_parameters          = {'counter' => 23}
        @event_job.arguments      = [named_parameters]
        @event_job.start!
        assert_equal false, @event_job.work(@worker), @event_job.inspect
        assert_equal true, @event_job.completed?, @event_job.attributes
        assert_equal 27, @event_job.priority
        assert_equal({'result' => 3645}, @event_job.result)
        assert_equal({'counter' => 23, 'before_event' => 3, 'after_event' => 3}, @event_job.arguments.first)
      end
    end
  end
end

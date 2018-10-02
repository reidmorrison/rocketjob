require_relative '../test_helper'

class ModelTest < Minitest::Test
  class SimpleJob < RocketJob::Job
    include RocketJob::Batch

    self.destroy_on_complete = false
    self.collect_output      = true
    self.slice_size          = 10

    def perform(record)
      record
    end
  end

  describe 'RocketJob::Batch::Model' do
    before do
      @blah_exception = begin
        begin
          blah
        rescue StandardError => exc
          exc
        end
      end
    end

    after do
      @job.destroy if @job && !@job.new_record?
    end

    describe '#exception' do
      it 'saves' do
        @job           = SimpleJob.new
        @job.exception = RocketJob::JobException.from_exception(@blah_exception)
        assert_equal true, @job.save!
      end

      it 'fails' do
        @job = SimpleJob.new
        assert_equal true, @job.fail!(@blah_exception)
      end
    end
  end
end

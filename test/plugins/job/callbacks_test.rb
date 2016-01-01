require_relative '../../test_helper'

# Unit Test for RocketJob::Job
class CallbacksTest < Minitest::Test
  # This job adds each callback as they run into an array
  class BeforePerformJob < RocketJob::Job
    before_perform do
      arguments.first << 'before_perform_block'
    end

    before_perform :before_perform_method

    def perform(list)
      list << 'perform'
    end

    private

    def before_perform_method
      arguments.first << 'before_perform_method'
    end

  end

  # This job adds each callback as they run into an array
  class AfterPerformJob < RocketJob::Job
    after_perform do
      arguments.first << 'after_perform_block'
    end

    after_perform :after_perform_method

    def perform(list)
      list << 'perform'
    end

    private

    def after_perform_method
      arguments.first << 'after_perform_method'
    end

  end

  # This job adds each callback as they run into an array
  class AroundPerformJob < RocketJob::Job
    around_perform do  |job, block|
      arguments.first << 'around_perform_block_before'
      block.call
      arguments.first << 'around_perform_block_after'
    end

    around_perform :around_perform_method

    def perform(list)
      list << 'perform'
    end

    private

    def around_perform_method
      arguments.first << 'around_perform_method_before'
      yield
      arguments.first << 'around_perform_method_after'
    end

  end

  # This job adds each callback as they run into an array
  class CombinedPerformJob < RocketJob::Job
    before_perform do
      arguments.first << 'before_perform_block'
    end

    after_perform do
      arguments.first << 'after_perform_block'
    end

    around_perform do  |job, block|
      arguments.first << 'around_perform_block_before'
      block.call
      arguments.first << 'around_perform_block_after'
    end

    before_perform :before_perform_method

    around_perform :around_perform_method

    after_perform :after_perform_method

    def perform(list)
      list << 'perform'
    end

    private

    def before_perform_method
      arguments.first << 'before_perform_method'
    end

    def around_perform_method(&block)
      arguments.first << 'around_perform_method_before'
      block.call
      arguments.first << 'around_perform_method_after'
    end

    def after_perform_method
      arguments.first << 'after_perform_method'
    end

  end

  describe RocketJob::Plugins::Job::Callbacks do
    after do
      @job.destroy if @job && !@job.new_record?
    end

    describe '#before_perform' do
      it 'runs blocks and functions' do
        @job = BeforePerformJob.new(arguments: [[]])
        @job.perform_now
        assert @job.completed?, @job.attributes.ai
        expected = %w(before_perform_block before_perform_method perform)
        assert_equal expected, @job.arguments.first, 'Sequence of before_perform callbacks is incorrect'
      end
    end

    describe '#after_perform' do
      it 'runs blocks and functions' do
        @job = AfterPerformJob.new(arguments: [[]])
        @job.perform_now
        assert @job.completed?, @job.attributes.ai
        expected = %w(perform after_perform_method after_perform_block)
        assert_equal expected, @job.arguments.first, 'Sequence of after_perform callbacks is incorrect'
      end
    end

    describe '#around_perform' do
      it 'runs blocks and functions' do
        @job = AroundPerformJob.new(arguments: [[]])
        @job.perform_now
        assert @job.completed?, @job.attributes.ai
        expected = %w(around_perform_block_before around_perform_method_before perform around_perform_method_after around_perform_block_after)
        assert_equal expected, @job.arguments.first, 'Sequence of around_perform callbacks is incorrect'
      end
    end

    describe 'all callbacks' do
      it 'runs them in the right order' do
        @job = CombinedPerformJob.new(arguments: [[]])
        @job.perform_now
        assert @job.completed?, @job.attributes.ai
        expected = %w(before_perform_block around_perform_block_before before_perform_method around_perform_method_before perform after_perform_method around_perform_method_after around_perform_block_after after_perform_block)
        assert_equal expected, @job.arguments.first, 'Sequence of around_perform callbacks is incorrect'
      end
    end

  end
end

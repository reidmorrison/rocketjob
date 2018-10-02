require_relative '../test_helper'

class OnDemandBatchJobTest < Minitest::Test
  describe RocketJob::Jobs::OnDemandBatchJob do
    describe '#valid?' do
      it 'code is parsable' do
        job = RocketJob::Jobs::OnDemandBatchJob.new(code: 'row')
        assert job.valid?
      end

      it 'code is not parsable' do
        job = RocketJob::Jobs::OnDemandBatchJob.new(code: '{oh no')
        refute job.valid?
      end

      it 'before_code is parsable' do
        job = RocketJob::Jobs::OnDemandBatchJob.new(code: 'row', before_code: 'true')
        assert job.valid?
      end

      it 'before_code is not parsable' do
        job = RocketJob::Jobs::OnDemandBatchJob.new(code: 'row', before_code: '{oh no')
        refute job.valid?
      end

      it 'after_code is parsable' do
        job = RocketJob::Jobs::OnDemandBatchJob.new(code: 'row', after_code: 'true')
        assert job.valid?
      end

      it 'after_code is not parsable' do
        job = RocketJob::Jobs::OnDemandBatchJob.new(code: 'row', after_code: '{oh no')
        refute job.valid?
      end
    end

    describe '#perform' do
      it 'runs code' do
        job = RocketJob::Jobs::OnDemandBatchJob.new(code: 'row + 1', collect_output: true)
        job.upload do |stream|
          stream << 1
          stream << 2
          stream << 3
        end
        job.perform_now
        assert job.completed?, -> { job.ai }
        assert_equal 1, job.output.count
        assert_equal [2, 3, 4], job.output.first.to_a
        job.cleanup!
      end

      it 'runs before code' do
        before_code = <<~CODE
          upload do |stream|
            stream << 1
            stream << 2
            stream << 3
          end
        CODE
        job = RocketJob::Jobs::OnDemandBatchJob.new(
          before_code:    before_code,
          code:           'row + 1',
          collect_output: true
        )
        job.perform_now
        assert job.completed?, -> { job.ai }
        assert_equal 1, job.output.count
        assert_equal [2, 3, 4], job.output.first.to_a
        job.cleanup!
      end

      it 'runs after code' do
        before_code = <<~CODE
          upload do |stream|
            stream << 1
            stream << 2
            stream << 3
          end
        CODE
        after_code = <<~CODE
          statistics['after'] = 413
        CODE
        job = RocketJob::Jobs::OnDemandBatchJob.new(
          before_code:    before_code,
          after_code:     after_code,
          code:           'row + 1',
          collect_output: true
        )
        job.perform_now
        assert job.completed?, -> { job.ai }
        assert_equal 1, job.output.count
        assert_equal [2, 3, 4], job.output.first.to_a
        job.cleanup!
        assert_equal 413, job.statistics['after']
      end
    end
  end
end

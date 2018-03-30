require_relative '../test_helper'

class GeneralizedJobTest < Minitest::Test
  describe RocketJob::Jobs::GeneralizedJob do
    before do
      RocketJob::Jobs::GeneralizedJob.delete_all
    end

    describe '#perform' do
      it 'hello world' do
        code = <<~CODE
          logger.info 'Hello World'
        CODE

        job = RocketJob::Jobs::GeneralizedJob.new(code: code)
        job.perform_now
      end

      it 'retain output' do
        code = <<~CODE
          {'value' => 'h' * 24}
        CODE

        job = RocketJob::Jobs::GeneralizedJob.new(
          code:           code,
          collect_output: true
        )
        job.perform_now
        assert_equal 'h' * 24, job.result['value']
      end

      it 'accepts input data' do
        code = <<~CODE
          {'value' => data['a'] * data['b']}
        CODE

        job = RocketJob::Jobs::GeneralizedJob.new(
          code:           code,
          collect_output: true,
          data:           {'a' => 10, 'b' => 2}
        )
        job.perform_now
        assert_equal 20, job.result['value']
      end

      it 'validates code' do
        code = <<~CODE
          def bad code
        CODE

        job = RocketJob::Jobs::GeneralizedJob.new(code: code)
        refute job.valid?
        assert_raises Mongoid::Errors::Validations do
          job.perform_now
        end
      end
    end
  end
end

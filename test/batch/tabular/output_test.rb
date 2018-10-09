require_relative '../../test_helper'

module Batch
  module Tabular
    class OutputTest < Minitest::Test
      class SimpleOutputJob < RocketJob::Job
        include RocketJob::Batch
        include RocketJob::Batch::Tabular::Output

        self.destroy_on_complete = false
        self.collect_output      = true
        self.slice_size          = 3

        def perform(record)
          record
        end
      end

      describe 'csv format' do
        before do
          assert @job = SimpleOutputJob.new(tabular_output_header: %w[one two three])
          @job.upload do |stream|
            stream << %w[1 2 3]
            stream << nil
            stream << %w[4 5 6]
            stream << %w[7 8 9]
          end
          @job.perform_now
          @io = StringIO.new
          @job.download(@io)
        end

        describe '#tabular_output_header' do
          it 'parses the header' do
            assert_equal %w[one two three], @job.tabular_output_header
          end
        end

        describe '#perform' do
          it 'renders each row with header' do
            lines = [
              'one,two,three',
              '1,2,3',
              '',
              '4,5,6',
              '7,8,9'
            ]
            assert_equal lines, @io.string.lines.collect(&:chomp)
          end
        end
      end

      describe 'json format' do
        before do
          assert @job = SimpleOutputJob.new(tabular_output_format: :json)
          @job.upload do |stream|
            stream << {first: 1, second: 2, third: 3}
            stream << ''
            stream << {first: 4, second: 5, third: 6}
            stream << {first: 7, second: 8, third: 9}
          end
          @job.perform_now
          @io = StringIO.new
          @job.download(@io)
        end

        describe '#tabular_output_header' do
          it 'does not have an output header' do
            refute @job.tabular_output_header
          end
        end

        describe '#perform' do
          it 'renders each row with header' do
            lines = [
              '{"first":1,"second":2,"third":3}',
              '',
              '{"first":4,"second":5,"third":6}',
              '{"first":7,"second":8,"third":9}'
            ]
            assert_equal lines, @io.string.lines.collect(&:chomp)
          end
        end
      end
    end
  end
end

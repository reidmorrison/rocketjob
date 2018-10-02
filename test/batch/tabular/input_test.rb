require_relative '../../test_helper'

module Tabular
  class InputTest < Minitest::Test

    class SimpleInputJob < RocketJob::Job
      include RocketJob::Batch
      include RocketJob::Batch::Tabular::Input

      self.destroy_on_complete = false
      self.collect_output      = true
      self.slice_size          = 3

      def perform(record)
        record
      end
    end

    describe 'with job' do
      before do
        assert @job = SimpleInputJob.new
        @job.upload do |stream|
          stream << 'first,second,third'
          stream << '1,2,3'
          stream << ''
          stream << '4,5,6'
          stream << '7,8,9'
        end
        @job.perform_now
        @io = StringIO.new
        @job.download(@io)
      end

      describe '#tabular_input_header' do
        it 'parses the header' do
          assert header = @job.tabular_input_header
          assert_equal %w(first second third), header
        end
      end

      describe '#tabular_input_process_first_slice' do
        it 'processes the first and subsequent slices' do
          lines = [
            '["first", "second", "third"]',
            '{"first"=>"1", "second"=>"2", "third"=>"3"}',
            '',
            '{"first"=>"4", "second"=>"5", "third"=>"6"}',
            '{"first"=>"7", "second"=>"8", "third"=>"9"}'
          ]
          assert_equal lines, @io.string.lines.collect(&:chomp)
        end
      end
    end

    describe 'custom header job' do
      before do
        assert @job = SimpleInputJob.new(tabular_input_header: %w(first second third))
        @job.upload do |stream|
          stream << '1,2,3'
          stream << ''
          stream << '4,5,6'
          stream << '7,8,9'
        end
        @job.perform_now
        @io = StringIO.new
        @job.download(@io)
      end

      describe '#tabular_input_process_first_slice' do
        it 'processes the first and subsequent slices' do
          lines = [
            '{"first"=>"1", "second"=>"2", "third"=>"3"}',
            '',
            '{"first"=>"4", "second"=>"5", "third"=>"6"}',
            '{"first"=>"7", "second"=>"8", "third"=>"9"}'
          ]
          assert_equal lines, @io.string.lines.collect(&:chomp)
        end
      end

    end

    describe 'json job' do
      before do
        assert @job = SimpleInputJob.new(tabular_input_format: :json)
        @job.upload do |stream|
          stream << {first: 1, second: 2, third: 3}.to_json
          stream << ''
          stream << {first: 4, second: 5, third: 6}.to_json
          stream << {first: 7, second: 8, third: 9}.to_json
        end
        @job.perform_now
        @io = StringIO.new
        @job.download(@io)
      end

      describe '#tabular_input_process_first_slice' do
        it 'processes the first and subsequent slices' do
          lines = [
            '{"first"=>1, "second"=>2, "third"=>3}',
            '',
            '{"first"=>4, "second"=>5, "third"=>6}',
            '{"first"=>7, "second"=>8, "third"=>9}'
          ]
          assert_equal lines, @io.string.lines.collect(&:chomp)
        end
      end
    end
  end
end

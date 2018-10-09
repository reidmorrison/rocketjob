require_relative '../test_helper'

module Batch
  class TabularTest < Minitest::Test

    class ArrayInputOutputJob < RocketJob::Job
      include RocketJob::Batch
      include RocketJob::Batch::Tabular::Input
      include RocketJob::Batch::Tabular::Output

      self.destroy_on_complete = false
      self.collect_output      = true
      self.slice_size          = 3

      def perform(record)
        # Handle blank lines ( as nil )
        record.values if record
      end
    end

    class HashInputOutputJob < RocketJob::Job
      include RocketJob::Batch
      include RocketJob::Batch::Tabular::Input
      include RocketJob::Batch::Tabular::Output

      self.destroy_on_complete = false
      self.collect_output      = true
      self.slice_size          = 3

      def perform(record)
        record
      end
    end

    # Useful for "sanity" checking first slice before letting workers process the remaining slices.
    class SpecializedFirstSliceJob < RocketJob::Job
      include RocketJob::Batch
      include RocketJob::Batch::Tabular::Input
      include RocketJob::Batch::Tabular::Output

      attr_accessor :specialized_first_slice

      self.destroy_on_complete   = false
      self.collect_output        = true
      self.slice_size            = 3
      self.tabular_output_header = %w(one two three)

      def perform(record)
        # Handle blank lines ( as nil )
        record.values if record
      end

      private

      # Overrides RocketJob::Batch::Tabular::Input#tabular_input_process_first_slice
      def tabular_input_process_first_slice
        # Instead of calling perform super will call this block
        super do |row|
          self.specialized_first_slice = true
          perform(row)
        end
      end
    end

    describe RocketJob::Batch::Tabular do
      describe 'csv format' do
        before do
          assert @job = ArrayInputOutputJob.new(tabular_output_header: %w(one two three))
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
          @json_lines = [
            '{"first":1,"second":2,"third":3}',
            '',
            '{"first":4,"second":5,"third":6}',
            '{"first":7,"second":8,"third":9}'
          ]

          assert @job = HashInputOutputJob.new(tabular_input_format: :json, tabular_output_format: :json)
          @job.upload(StringIO.new(@json_lines.join("\n")))
          @job.perform_now
          @io = StringIO.new
          @job.download(@io)
        end

        describe '#tabular_input_header' do
          it 'does not have headers' do
            refute @job.tabular_input_header
            refute @job.tabular_output_header
          end
        end

        describe '#tabular_input_process_first_slice' do
          it 'processes the first and subsequent slices' do
            assert_equal @json_lines, @io.string.lines.collect(&:chomp)
          end
        end
      end

      describe 'custom header job' do
        before do
          assert @job = ArrayInputOutputJob.new(
            tabular_input_header:  %w(first second third),
            tabular_output_header: %w(one two three)
          )
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

      describe 'process with block' do
        before do
          assert @job = SpecializedFirstSliceJob.new
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
          #assert @job.specialized_first_slice
        end

        describe '#tabular_input_process_first_slice' do
          it 'processes the first and subsequent slices' do
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
    end
  end
end

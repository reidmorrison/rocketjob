require_relative '../../test_helper'

module Batch
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

      describe RocketJob::Batch::Tabular::Input do
        let :job do
          SimpleInputJob.new
        end

        let :data do
          [
            'first,second,third',
            '1,2,3',
            '',
            '4,5,6',
            '7,8,9'
          ]
        end

        let :expected_output do
          [
            '{"first"=>"1", "second"=>"2", "third"=>"3"}',
            '',
            '{"first"=>"4", "second"=>"5", "third"=>"6"}',
            '{"first"=>"7", "second"=>"8", "third"=>"9"}'
          ]
        end

        let :run_job do
          io = StringIO.new(data.join("\n"))
          job.upload(io)
          job.perform_now
          job
        end

        let :output do
          io = StringIO.new
          run_job.download(io)
          io.string
        end

        describe 'with csv input' do
          it 'parses the header' do
            assert_equal %w(first second third), run_job.tabular_input_header
          end

          it 'has correct output' do
            assert_equal expected_output, output.lines.collect(&:chomp)
          end

          describe 'tabular_input_mode: :array' do
            let :job do
              SimpleInputJob.new(tabular_input_mode: :array)
            end

            it 'parses the header' do
              assert_equal %w(first second third), run_job.tabular_input_header
            end

            it 'has correct output' do
              assert_equal expected_output, output.lines.collect(&:chomp)
            end
          end

          describe 'tabular_input_mode: :hash' do
            let :job do
              SimpleInputJob.new(tabular_input_mode: :hash)
            end

            it 'does not set the tabular_input_header' do
              assert_nil run_job.tabular_input_header
            end

            it 'has correct output' do
              assert_equal expected_output, output.lines.collect(&:chomp)
            end
          end

          describe 'custom header' do
            let :job do
              SimpleInputJob.new(tabular_input_header: %w(first second third))
            end

            # Data without a header since it is supplied explicitly
            let :data do
              [
                '1,2,3',
                '',
                '4,5,6',
                '7,8,9'
              ]
            end

            it 'retains tabular_input_header' do
              assert_equal %w(first second third), run_job.tabular_input_header
            end

            it 'has correct output' do
              assert_equal expected_output, output.lines.collect(&:chomp)
            end
          end
        end

        describe 'with json input' do
          let :job do
            SimpleInputJob.new(tabular_input_format: :json)
          end

          let :data do
            [
              {first: 1, second: 2, third: 3}.to_json,
              '',
              {first: 4, second: 5, third: 6}.to_json,
              {first: 7, second: 8, third: 9}.to_json
            ]
          end

          it 'does not set the tabular_input_header' do
            assert_nil run_job.tabular_input_header
          end

          it 'has correct output' do
            lines = [
              '{"first"=>1, "second"=>2, "third"=>3}',
              '',
              '{"first"=>4, "second"=>5, "third"=>6}',
              '{"first"=>7, "second"=>8, "third"=>9}'
            ]
            assert_equal lines, output.lines.collect(&:chomp)
          end
        end
      end
    end
  end
end
